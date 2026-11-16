import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_chart.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';
import 'insights_harness.dart' show FixedToday;

final DateTime today = DateTime(2026, 11, 15);

Vice habit(String id, int created) => Vice(
  id: id,
  name: id,
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(created),
  archived: false,
);

AskCard card(
  String title,
  String sql, {
  String type = 'number',
  String x = '',
  List<String> y = const <String>['entries'],
  String xKind = 'none',
}) => AskCard(
  title: title,
  explain: 'Explained $title',
  sql: sql,
  chart: AskChartSpec(
    type: AskChartType.values.byName(type),
    x: x,
    y: y,
    xKind: AskXKind.values.byName(xKind),
  ),
);

AskAnswer cards(List<AskCard> c) => AskAnswer(kind: AskKind.answer, cards: c);

const String countSql =
    'SELECT count(*) AS entries FROM entries WHERE habit_id = 1';
const String hourSql =
    'SELECT hour, count(*) AS n FROM entries GROUP BY hour ORDER BY hour';

class FakeAsk implements AskJournal {
  FakeAsk(this.reply);

  final Future<AskAnswer> Function(String question) reply;
  final List<String> asked = <String>[];
  final List<List<AskTurn>> histories = <List<AskTurn>>[];

  @override
  Future<AskAnswer> ask(
    String question, {
    required List<({int id, Vice vice})> habits,
    required DateTime today,
    List<AskTurn> history = const <AskTurn>[],
  }) {
    asked.add(question);
    histories.add(history);
    return reply(question);
  }
}

void main() {
  final List<Vice> vices = <Vice>[habit('Wine', 0), habit('Beer', 1)];
  final List<ViceActivity> entries = <ViceActivity>[
    fakeActivity('Wine', 2, DateTime(2026, 11, 15, 12)),
    fakeActivity('Wine', 3, DateTime(2026, 11, 14, 20)),
    fakeActivity('Wine', 9, DateTime(2026, 10, 1, 20)),
    fakeActivity('Beer', 1, DateTime(2026, 11, 14, 9)),
  ];

  Widget app(AskJournal? service) => ProviderScope(
    overrides: [
      userProvider.overrideWith((ref) => Stream.value(FakeUser('a'))),
      offlineProvider.overrideWith((ref) => Stream.value(false)),
      todayProvider.overrideWith(() => FixedToday(today)),
      askJournalProvider.overrideWithValue(service),
      viceListProvider.overrideWithValue(AsyncData<List<Vice>>(vices)),
      viceActivityRangeProvider.overrideWith(
        (Ref ref, ActivityRange range) =>
            AsyncData<List<ViceActivity>>(entries),
      ),
      allDayNotesProvider.overrideWithValue(
        const AsyncData<List<DayNote>>(<DayNote>[]),
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

  group('AskPage', () {
    testWidgets('runs each card\'s SQL on the device and shows the result', (
      WidgetTester tester,
    ) async {
      final FakeAsk service = FakeAsk(
        (_) async => cards(<AskCard>[
          card('How many glasses', countSql),
          card(
            'By hour',
            hourSql,
            type: 'bar',
            x: 'hour',
            y: <String>['n'],
            xKind: 'hour',
          ),
        ]),
      );
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await ask(tester, 'When do I drink?');

      expect(service.asked, <String>['When do I drink?']);
      expect(find.text('How many glasses'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.byType(AskChart), findsNWidgets(2));
      expect(find.text(AskPage.couldNotRun), findsNothing);
      expect(find.text(AskPage.onDevice.toUpperCase()), findsNWidgets(2));
      expect(find.text(countSql), findsNothing);
      await tester.tap(find.text(AskPage.showQuery).first);
      await tester.pumpAndSettle();
      expect(find.text(countSql), findsOneWidget);
      expect(find.text(AskPage.hideQuery), findsOneWidget);
    });

    for (final String bad in <String>[
      'DROP TABLE entries',
      'SELECT 1; SELECT 2',
    ]) {
      testWidgets('refuses "$bad" and still shows the other cards', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          app(
            FakeAsk(
              (_) async => cards(<AskCard>[
                card('Bad one', bad),
                card('Good one', countSql),
              ]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await ask(tester, 'Anything?');
        expect(find.text(AskPage.couldNotRun), findsOneWidget);
        expect(find.text('Good one'), findsOneWidget);
        expect(find.text('3'), findsWidgets);
        expect(find.byType(AskChart), findsOneWidget);
      });
    }

    testWidgets('hands a why to Insights', (WidgetTester tester) async {
      await tester.pumpWidget(
        app(FakeAsk((_) async => const AskAnswer(kind: AskKind.needsInsights))),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'Why do I drink on Fridays?');
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
          FakeAsk(
            (_) async => const AskAnswer(
              kind: AskKind.cannotAnswer,
              reason: AskReason.unknownHabit,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'How many cigars?');
      expect(find.text(AskPage.cannot), findsOneWidget);
      expect(
        find.text(AskPage.cannotDetail(AskReason.unknownHabit)),
        findsOneWidget,
      );
    });

    testWidgets('a failed ask says so and keeps the question', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        app(FakeAsk((_) async => throw const AskFailed('api_error'))),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'First?');
      expect(find.text(AskPage.failed), findsOneWidget);
      expect(find.text('First?'), findsOneWidget);
    });

    testWidgets('a follow-up sends the earlier turn and its answer', (
      WidgetTester tester,
    ) async {
      final AskAnswer first = cards(<AskCard>[card('Count', countSql)]);
      final FakeAsk service = FakeAsk((_) async => first);
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await ask(tester, 'One?');
      await ask(tester, 'Two?');
      expect(service.histories[0], isEmpty);
      expect(service.histories[1], hasLength(1));
      expect(service.histories[1].single.question, 'One?');
      expect(service.histories[1].single.answer.toJson(), first.toJson());
    });

    testWidgets('New question clears the cards and the history', (
      WidgetTester tester,
    ) async {
      final FakeAsk service = FakeAsk(
        (_) async => cards(<AskCard>[card('Count', countSql)]),
      );
      await tester.pumpWidget(app(service));
      await tester.pumpAndSettle();
      await ask(tester, 'One?');
      expect(find.text('Count'), findsOneWidget);
      await tester.tap(find.text(AskPage.newQuestion));
      await tester.pumpAndSettle();
      expect(find.text('Count'), findsNothing);
      expect(find.text('One?'), findsNothing);
      await ask(tester, 'Two?');
      expect(service.histories.last, isEmpty);
    });

    testWidgets('switched off, it says where to turn it on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith((ref) => Stream.value(FakeUser('a'))),
            todayProvider.overrideWith(() => FixedToday(today)),
            askJournalProvider.overrideWithValue(null),
            viceListProvider.overrideWithValue(AsyncData<List<Vice>>(vices)),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const AskPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AskPage.off), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
