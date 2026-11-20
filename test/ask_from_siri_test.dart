import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/analyst/analyst_setting.dart';
import 'package:tracker/app_lock/app_lock.dart';
import 'package:tracker/ask/ask_answer.dart';
import 'package:tracker/ask/ask_from_siri.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/ask/ask_page.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/sealed.dart';
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

import 'ask_page_test.dart' show FakeAsk, card, cards, countSql;
import 'fake_sealer.dart';
import 'fakes.dart';
import 'insights_harness.dart' show FixedToday;

final DateTime today = DateTime(2026, 11, 15);

final List<Vice> vices = <Vice>[
  Vice(
    id: 'Wine',
    name: 'Wine',
    unit: Unit.drink,
    ownerID: ownerID,
    createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
    archived: false,
  ),
];

/// Everything the ready check waits for, settled, unless a test says not.
List<Override> ready({
  Stream<User?>? users,
  AskJournal? service,
  bool allowed = true,
  bool profileRead = true,
  Future<void>? choiceRead,
  bool locked = false,
  bool keyLoaded = true,
}) => <Override>[
  userProvider.overrideWith((ref) => users ?? Stream.value(FakeUser('a'))),
  userProfileProvider.overrideWith(
    (ref) =>
        profileRead ? Stream.value(FakeUser('a')) : const Stream<User?>.empty(),
  ),
  askJournalProvider.overrideWithValue(service),
  claudeAllowedProvider.overrideWithValue(allowed),
  askJournalChoiceReadProvider.overrideWith(
    (ref) => choiceRead ?? Future<void>.value(),
  ),
  appLockSavedProvider.overrideWithValue(locked),
  sealerProvider.overrideWithValue(keyLoaded ? FakeSealer() : null),
  viceListProvider.overrideWithValue(AsyncData<List<Vice>>(vices)),
];

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the switch is known once its saved choice is read', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AskJournalEnabled.key: true,
    });
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(askJournalEnabledProvider), isFalse);
    await c.read(askJournalChoiceReadProvider.future);
    expect(c.read(askJournalEnabledProvider), isTrue);
  });

  group('siriQuestionReadyProvider', () {
    Future<ProviderContainer> containerWith(List<Override> overrides) async {
      final ProviderContainer c = ProviderContainer(overrides: overrides);
      addTearDown(c.dispose);
      c.listen(siriQuestionReadyProvider, (_, _) {});
      c.listen(userProvider, (_, _) {});
      c.listen(userProfileProvider, (_, _) {});
      c.listen(askJournalChoiceReadProvider, (_, _) {});
      await settle();
      return c;
    }

    test('asks when Ask is on for this account', () async {
      final ProviderContainer c = await containerWith(
        ready(service: FakeAsk((_) async => cards(<AskCard>[]))),
      );
      c.read(pendingSiriQuestionProvider.notifier).request('  How many?  ');
      expect(c.read(siriQuestionReadyProvider), (
        question: 'How many?',
        outcome: SiriAskOutcome.ask,
      ));
    });

    test('waits for the saved switch before saying it is off', () async {
      final Completer<void> read = Completer<void>();
      final ProviderContainer c = await containerWith(
        ready(choiceRead: read.future),
      );
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      expect(c.read(siriQuestionReadyProvider), isNull);
      read.complete();
      await settle();
      expect(c.read(siriQuestionReadyProvider)?.outcome, SiriAskOutcome.turnOn);
    });

    test('waits for the profile before saying the email is missing', () async {
      final ProviderContainer notYet = await containerWith(
        ready(allowed: false, profileRead: false),
      );
      notYet.read(pendingSiriQuestionProvider.notifier).request('How many?');
      expect(notYet.read(siriQuestionReadyProvider), isNull);

      final ProviderContainer read = await containerWith(ready(allowed: false));
      read.read(pendingSiriQuestionProvider.notifier).request('How many?');
      expect(
        read.read(siriQuestionReadyProvider)?.outcome,
        SiriAskOutcome.verifyEmail,
      );
    });

    test('waits behind the app lock and for the journal key', () async {
      for (final List<Override> overrides in <List<Override>>[
        ready(locked: true),
        ready(keyLoaded: false),
      ]) {
        final ProviderContainer c = await containerWith(overrides);
        c.read(pendingSiriQuestionProvider.notifier).request('How many?');
        expect(c.read(pendingSiriQuestionProvider), 'How many?');
        expect(c.read(siriQuestionReadyProvider), isNull);
      }
    });

    test('keeps a question that came before Auth restored the session, and '
        'drops it when another account signs in', () async {
      final StreamController<User?> users = StreamController<User?>();
      addTearDown(users.close);
      final ProviderContainer c = await containerWith(
        ready(users: users.stream),
      );
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      users.add(FakeUser('a'));
      await settle();
      expect(c.read(pendingSiriQuestionProvider), 'How many?');

      users.add(FakeUser('b'));
      await settle();
      expect(c.read(pendingSiriQuestionProvider), isNull);
    });

    test('drops it on sign-out, and refuses one while signed out', () async {
      final StreamController<User?> users = StreamController<User?>();
      addTearDown(users.close);
      final ProviderContainer c = await containerWith(
        ready(users: users.stream),
      );
      users.add(FakeUser('a'));
      await settle();
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      users.add(null);
      await settle();
      expect(c.read(pendingSiriQuestionProvider), isNull);
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      expect(c.read(pendingSiriQuestionProvider), isNull);
    });

    test('refuses a question Ask could not send', () async {
      final ProviderContainer c = await containerWith(ready());
      c
          .read(pendingSiriQuestionProvider.notifier)
          .request('x' * (CallableAskJournal.maxQuestion + 1));
      expect(c.read(pendingSiriQuestionProvider), isNull);
      c.read(pendingSiriQuestionProvider.notifier).request('   ');
      expect(c.read(pendingSiriQuestionProvider), isNull);
    });
  });

  group('openSiriQuestion', () {
    late WidgetRef widgetRef;
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final GlobalKey<ScaffoldMessengerState> messenger =
        GlobalKey<ScaffoldMessengerState>();

    Future<ProviderContainer> host(WidgetTester tester) async {
      final ProviderContainer c = ProviderContainer(overrides: ready());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            navigatorKey: navigator,
            scaffoldMessengerKey: messenger,
            home: Scaffold(
              body: Consumer(
                builder: (BuildContext context, WidgetRef ref, _) {
                  widgetRef = ref;
                  return const Text('Today');
                },
              ),
            ),
            onGenerateRoute: (RouteSettings settings) =>
                MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) =>
                      Scaffold(body: Text('route ${settings.name}')),
                ),
          ),
        ),
      );
      return c;
    }

    void open(SiriAskOutcome outcome) => openSiriQuestion(
      navigator.currentState!,
      messenger.currentState!,
      widgetRef,
      (question: 'How many?', outcome: outcome),
    );

    testWidgets('switched off: Settings, saying why, with nothing kept', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await host(tester);
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      open(SiriAskOutcome.turnOn);
      await tester.pumpAndSettle();
      expect(find.text('route /settings'), findsOneWidget);
      expect(find.text(siriTurnOnNotice), findsOneWidget);
      expect(c.read(pendingSiriQuestionProvider), isNull);
    });

  });

  group('AskPage with a question from Siri', () {
    Widget app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const AskPage(),
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          builder: (_) => Text('route ${settings.name}'),
        ),
      ),
    );

    ProviderContainer container(FakeAsk service) {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          ...ready(service: service),
          investigatorProvider.overrideWithValue(null),
          offlineProvider.overrideWith((ref) => Stream.value(false)),
          todayProvider.overrideWith(() => FixedToday(today)),
          viceActivityRangeProvider.overrideWith(
            (Ref ref, ActivityRange range) =>
                const AsyncData<List<ViceActivity>>(<ViceActivity>[]),
          ),
          allDayNotesProvider.overrideWithValue(
            const AsyncData<List<DayNote>>(<DayNote>[]),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('asks it once, as a typed question would be', (
      WidgetTester tester,
    ) async {
      final FakeAsk service = FakeAsk(
        (_) async => cards(<AskCard>[card('How many glasses', countSql)]),
      );
      final ProviderContainer c = container(service);
      c.read(pendingSiriQuestionProvider.notifier).request('How many?');
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();

      expect(service.asked, <String>['How many?']);
      expect(c.read(pendingSiriQuestionProvider), isNull);
      expect(c.read(askSessionProvider).single.question, 'How many?');
      expect(find.text('How many glasses'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(service.asked, hasLength(1));
    });

    testWidgets('a second question waits for the first answer, then follows '
        'it up', (WidgetTester tester) async {
      final Completer<AskAnswer> first = Completer<AskAnswer>();
      final FakeAsk service = FakeAsk(
        (String q) => q == 'First?'
            ? first.future
            : Future<AskAnswer>.value(cards(<AskCard>[])),
      );
      final ProviderContainer c = container(service);
      c.read(pendingSiriQuestionProvider.notifier).request('First?');
      await tester.pumpWidget(app(c));
      await tester.pump();
      await tester.pump();
      expect(service.asked, <String>['First?']);

      c.read(pendingSiriQuestionProvider.notifier).request('Second?');
      await tester.pump();
      await tester.pump();
      expect(service.asked, <String>['First?']);
      expect(c.read(pendingSiriQuestionProvider), 'Second?');

      first.complete(cards(<AskCard>[card('How many glasses', countSql)]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(service.asked, <String>['First?', 'Second?']);
      expect(service.histories.last.single.question, 'First?');
      await tester.pumpAndSettle();
    });
  });
}
