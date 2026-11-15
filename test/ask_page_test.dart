import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/ask/ask_query.dart';
import 'package:tracker/ask/describe_query.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';
import 'insights_harness.dart' show FixedToday;

final DateTime today = DateTime(2026, 11, 15);

Vice vice(String id, {bool locked = false, int created = 0}) => Vice(
  id: id,
  name: id,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(created),
  archived: false,
  locked: locked,
);

const AskQuery wineThisWeek = AskQuery(
  side: AskSide(habit: 0, period: AskPeriod(AskPeriodType.lastDays, count: 7)),
  measure: AskMeasure.amount,
  shape: AskShape.total,
);

class FakeAsk implements AskJournal {
  FakeAsk(this.reply);

  final Future<AskParsed> Function(String question) reply;
  final List<String> asked = <String>[];

  @override
  Future<AskParsed> ask(
    String question, {
    required List<Vice> habits,
    required DateTime today,
  }) {
    asked.add(question);
    return reply(question);
  }
}

void main() {
  group('CallableAskJournal', () {
    final List<Vice> habits = <Vice>[
      vice('Wine'),
      Vice(
        id: 'v',
        name: 'Vape',
        unit: Unit.puff,
        ownerID: ownerID,
        createdAt: Timestamp.fromMillisecondsSinceEpoch(1),
        archived: true,
        unitLabel: 'pulls',
      ),
    ];

    Map<String, Object?> rawQuery() => <String, Object?>{
      'kind': 'query',
      'reason': 'none',
      'habit': 1,
      'measure': 'entries',
      'period': <String, Object?>{
        'type': 'all_time',
        'count': null,
        'from': null,
        'to': null,
      },
      'filter': <String, Object?>{
        'weekdays': <Object?>[],
        'from_hour': null,
        'to_hour': null,
        'tag': null,
      },
      'shape': 'total',
      'bucket': null,
      'condition': null,
      'threshold': null,
      'longest': null,
      'versus': null,
    };

    test('sends the question, today and the habit names alone', () async {
      final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
      final CallableAskJournal service = CallableAskJournal((data) async {
        sent.add(data);
        return <String, Object?>{'reason': 'ok', 'query': rawQuery()};
      });
      final AskParsed parsed = await service.ask(
        '  How often did I vape?  ',
        habits: habits,
        today: DateTime(2026, 11, 15, 14),
      );
      expect(sent, <Object?>[
        <String, Object?>{
          'question': 'How often did I vape?',
          'today': '2026-11-15',
          'weekday': 'Sunday',
          'habits': <Object?>[
            <String, Object?>{
              'name': 'Wine',
              'unit': 'drinks',
              'archived': false,
            },
            <String, Object?>{
              'name': 'Vape',
              'unit': 'pulls',
              'archived': true,
            },
          ],
        },
      ]);
      expect((parsed as AskRun).query.side.habit, 1);
    });

    test('a query that fails a check is cannot_answer', () async {
      final CallableAskJournal service = CallableAskJournal(
        (_) async => <String, Object?>{
          'reason': 'ok',
          'query': rawQuery()..['habit'] = 2,
        },
      );
      final AskParsed parsed = await service.ask(
        'x',
        habits: habits,
        today: today,
      );
      expect(parsed, isA<AskCannotAnswer>());
    });

    test('an empty or overlong question is never sent', () async {
      int calls = 0;
      final CallableAskJournal service = CallableAskJournal((_) async {
        calls++;
        return null;
      });
      expect(
        await service.ask(' ', habits: habits, today: today),
        isA<AskCannotAnswer>(),
      );
      expect(
        await service.ask('x' * 301, habits: habits, today: today),
        isA<AskCannotAnswer>(),
      );
      expect(calls, 0);
    });

    test('a reason other than ok is AskFailed', () async {
      final CallableAskJournal service = CallableAskJournal(
        (_) async => <String, Object?>{'reason': 'refusal', 'query': null},
      );
      await expectLater(
        service.ask('x', habits: habits, today: today),
        throwsA(
          isA<AskFailed>().having(
            (AskFailed e) => e.reason,
            'reason',
            'refusal',
          ),
        ),
      );
    });

    test('no answer within 10 s is a timeout', () {
      fakeAsync((FakeAsync async) {
        final CallableAskJournal service = CallableAskJournal(
          (_) => Completer<Object?>().future,
        );
        Object? error;
        service.ask('x', habits: habits, today: today).catchError((Object e) {
          error = e;
          return const AskNeedsInsights();
        });
        async.elapse(const Duration(seconds: 9));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<TimeoutException>());
      });
    });

    test('askHabits leaves out locked habits and lists oldest first', () {
      final List<Vice> sent = askHabits(<Vice>[
        vice('b', created: 2),
        vice('locked', locked: true),
        vice('a', created: 1),
      ]);
      expect(sent.map((Vice v) => v.id), <String>['a', 'b']);
    });
  });

  group('askJournalProvider', () {
    Future<AskJournal?> serviceWith({
      required bool? enabled,
      required User? user,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AskJournalEnabled.key: ?enabled,
      });
      final ProviderContainer container = ProviderContainer(
        overrides: [userProvider.overrideWith((ref) => Stream.value(user))],
      );
      addTearDown(container.dispose);
      container.listen(askJournalProvider, (_, _) {});
      await pumpEventQueue();
      return container.read(askJournalProvider);
    }

    test(
      'is a service only while switched on with someone signed in',
      () async {
        expect(
          await serviceWith(enabled: true, user: FakeUser('a')),
          isA<CallableAskJournal>(),
        );
        expect(await serviceWith(enabled: false, user: FakeUser('a')), isNull);
        expect(await serviceWith(enabled: true, user: null), isNull);
        expect(await serviceWith(enabled: null, user: FakeUser('a')), isNull);
      },
    );
  });

  group('AskPage', () {
    final Vice wine = vice('Wine');
    final List<ViceActivity> entries = <ViceActivity>[
      fakeActivity('Wine', 2, DateTime(2026, 11, 15, 12)),
      fakeActivity('Wine', 3, DateTime(2026, 11, 14, 20)),
      fakeActivity('Wine', 9, DateTime(2026, 10, 1, 20)),
    ];

    Widget app(AskJournal? service) => ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser('a'))),
        offlineProvider.overrideWith((ref) => Stream.value(false)),
        todayProvider.overrideWith(() => FixedToday(today)),
        askJournalProvider.overrideWithValue(service),
        viceListProvider.overrideWithValue(AsyncData<List<Vice>>(<Vice>[wine])),
        viceActivityRangeProvider.overrideWith(
          (Ref ref, ActivityRange range) =>
              AsyncData<List<ViceActivity>>(entries),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const AskPage(),
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          builder: (_) => Text('route ${settings.name}'),
        ),
      ),
    );

    Future<void> ask(WidgetTester tester, String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.tap(find.text(AskPage.ask));
      await tester.pumpAndSettle();
    }

    testWidgets('answers on the device and says the query in words', (
      WidgetTester tester,
    ) async {
      final FakeAsk service = FakeAsk((_) async => const AskRun(wineThisWeek));
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await ask(tester, 'How much wine this week?');
      expect(service.asked, <String>['How much wine this week?']);
      expect(find.text('How much wine this week?'), findsOneWidget);
      expect(find.text('5 drinks'), findsOneWidget);
      expect(
        find.text(describeQuery(wineThisWeek, <Vice>[wine])),
        findsOneWidget,
      );
      expect(find.text(AskPage.onDevice.toUpperCase()), findsOneWidget);
      expect(find.byType(AskBars), findsOneWidget);
    });

    testWidgets('hands a why to Insights', (WidgetTester tester) async {
      await tester.pumpWidget(
        app(FakeAsk((_) async => const AskNeedsInsights())),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'Why do I drink more on Fridays?');
      expect(find.text(AskPage.insights), findsOneWidget);
      await tester.tap(find.text(AskPage.openInsights));
      await tester.pumpAndSettle();
      expect(find.text('route /insights'), findsOneWidget);
    });

    testWidgets('says plainly what it cannot answer', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        app(
          FakeAsk((_) async => const AskCannotAnswer(AskReason.unknownHabit)),
        ),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'How many beers?');
      expect(find.text(AskPage.cannot), findsOneWidget);
      expect(
        find.text(AskPage.cannotDetail(AskReason.unknownHabit)),
        findsOneWidget,
      );
    });

    testWidgets('a failed call counts nothing, and keeps recent questions', (
      WidgetTester tester,
    ) async {
      int n = 0;
      await tester.pumpWidget(
        app(
          FakeAsk((_) async {
            if (n++ == 0) throw const AskFailed('api_error');
            return const AskRun(wineThisWeek);
          }),
        ),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'First?');
      expect(find.text(AskPage.failed), findsOneWidget);
      await ask(tester, 'Second?');
      expect(find.text('First?'), findsOneWidget);
      expect(find.text('Second?'), findsOneWidget);
      expect(find.text('5 drinks'), findsOneWidget);
    });

    testWidgets('switched off, it says where to turn it on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      expect(find.text(AskPage.off), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('AskJournalSetting', () {
    Widget app() => ProviderScope(
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const Scaffold(body: AskJournalSetting()),
      ),
    );

    Future<bool?> saved() async =>
        (await SharedPreferences.getInstance()).getBool(AskJournalEnabled.key);

    testWidgets('turning on says what is sent and asks first', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(AskJournalSetting.disclosure), findsOneWidget);
      for (final String word in <String>[
        'habits’ names',
        'Anthropic',
        'never sent',
        'this device',
        'training',
      ]) {
        expect(AskJournalSetting.disclosure, contains(word));
      }
      await tester.tap(find.text(AskJournalSetting.notNow));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isNull);

      await tester.tap(find.text(AskJournalSetting.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AskJournalSetting.turnOn));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(await saved(), isTrue);
    });

    testWidgets('turning off needs no asking', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AskJournalEnabled.key: true,
      });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(AskJournalSetting.disclosure), findsNothing);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(await saved(), isFalse);
    });
  });
}
