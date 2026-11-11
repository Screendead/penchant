import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/key_store.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import '../fake_account.dart';
import '../fakes.dart';

class _FakeToday extends Today {
  _FakeToday(this._start);

  final DateTime _start;

  @override
  DateTime build() => _start;
}

class _FakeActions implements RecoveryKeyActions {
  _FakeActions({this.outcome = const UnlockOpened(), this.fails = false});

  final UnlockOutcome outcome;
  final bool fails;
  int saved = 0;
  int dismissed = 0;
  int newJournals = 0;
  final List<Uint8List> unlocks = <Uint8List>[];

  @override
  Future<void> markSaved() async {
    if (fails) {
      throw StateError('keychain');
    }
    saved++;
  }

  @override
  Future<void> dismissCard() async => dismissed++;

  @override
  Future<UnlockOutcome> unlock(Uint8List recoveryKey) async {
    unlocks.add(recoveryKey);
    if (fails) {
      throw StateError('keychain');
    }
    return outcome;
  }

  @override
  Future<void> startNewJournal() async {
    if (fails) {
      throw StateError('keychain');
    }
    newJournals++;
  }
}

class _Locked extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() => state = true;
}

final _lockedProvider = NotifierProvider<_Locked, bool>(_Locked.new);

class _Waiting extends Notifier<bool> {
  @override
  bool build() => true;

  void arrive() => state = false;
}

final _waitingProvider = NotifierProvider<_Waiting, bool>(_Waiting.new);

final Uint8List _key = RecoveryKey.generate(Random(11));
final String _formatted = RecoveryKey.format(_key);

Widget _app(
  List<Override> overrides,
  Widget home, {
  bool enabled = true,
  bool signedIn = true,
}) => ProviderScope(
  overrides: <Override>[
    e2eeEnabledProvider.overrideWithValue(enabled),
    userProvider.overrideWith(
      (ref) => Stream<User?>.value(signedIn ? FakeUser('u') : null),
    ),
    ...overrides,
  ],
  child: MaterialApp(
    theme: appTheme(Brightness.light),
    routes: <String, WidgetBuilder>{
      RecoveryKeyPage.route: (_) => const RecoveryKeyPage(),
      '/pushed': (_) => const Scaffold(body: Text('pushed page')),
    },
    builder: (BuildContext context, Widget? child) =>
        RecoveryKeyGate(child: child!),
    home: home,
  ),
);

void main() {
  group('the Today card', () {
    final DateTime created = DateTime(2026, 11, 1, 22, 30);

    Future<void> pumpCard(
      WidgetTester tester, {
      required DateTime today,
      RecoveryKeyStatus? status,
      _FakeActions? actions,
    }) async {
      // A fresh scope, since a Notifier override is read once per scope.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(<Override>[
          todayProvider.overrideWith(() => _FakeToday(today)),
          recoveryKeyStatusProvider.overrideWithValue(
            status ??
                RecoveryKeyStatus(formatted: _formatted, keyCreatedAt: created),
          ),
          recoveryKeyActionsProvider.overrideWithValue(
            actions ?? _FakeActions(),
          ),
        ], const Scaffold(body: RecoveryKeyCard())),
      );
    }

    testWidgets('waits seven local days from the key', (tester) async {
      await pumpCard(tester, today: DateTime(2026, 11, 7));
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
      await pumpCard(tester, today: DateTime(2026, 11, 8));
      expect(find.text(RecoveryKeyCopy.cardTitle), findsOneWidget);
    });

    testWidgets('counts from the first entry when one is known', (
      tester,
    ) async {
      final RecoveryKeyStatus status = RecoveryKeyStatus(
        formatted: _formatted,
        keyCreatedAt: created,
        firstEntryAt: DateTime(2026, 11, 4, 9),
      );
      await pumpCard(tester, today: DateTime(2026, 11, 10), status: status);
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
      await pumpCard(tester, today: DateTime(2026, 11, 11), status: status);
      expect(find.text(RecoveryKeyCopy.cardTitle), findsOneWidget);
    });

    testWidgets('stays away once saved or dismissed', (tester) async {
      for (final RecoveryKeyStatus status in <RecoveryKeyStatus>[
        RecoveryKeyStatus(
          formatted: _formatted,
          keyCreatedAt: created,
          saved: true,
        ),
        RecoveryKeyStatus(
          formatted: _formatted,
          keyCreatedAt: created,
          cardDismissed: true,
        ),
      ]) {
        await pumpCard(tester, today: DateTime(2026, 12, 1), status: status);
        expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
      }
    });

    testWidgets('Not now hides it and records the dismissal', (tester) async {
      final _FakeActions actions = _FakeActions();
      await pumpCard(tester, today: DateTime(2026, 11, 8), actions: actions);
      await tester.tap(find.text(RecoveryKeyCopy.notNow));
      await tester.pump();
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
      expect(actions.dismissed, 1);
    });

    testWidgets('shows nothing while E2EE is off', (tester) async {
      await tester.pumpWidget(
        _app(
          <Override>[
            todayProvider.overrideWith(() => _FakeToday(DateTime(2026, 12))),
            recoveryKeyStatusProvider.overrideWithValue(
              RecoveryKeyStatus(formatted: _formatted, keyCreatedAt: created),
            ),
          ],
          const Scaffold(body: RecoveryKeyCard()),
          enabled: false,
        ),
      );
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
    });

    testWidgets('shows nothing while no key exists', (tester) async {
      await tester.pumpWidget(
        _app(<Override>[
          todayProvider.overrideWith(() => _FakeToday(DateTime(2030))),
        ], const Scaffold(body: RecoveryKeyCard())),
      );
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
    });
  });

  group('where the journal key is kept', () {
    Future<void> openPage(WidgetTester tester, RecoveryKeyStatus status) async {
      await tester.pumpWidget(
        _app(<Override>[
          recoveryKeyStatusProvider.overrideWithValue(status),
        ], const RecoveryKeyPage()),
      );
      await tester.pumpAndSettle();
    }

    final DateTime created = DateTime(2026, 11, 1);

    testWidgets('says iCloud Keychain for a synced key', (tester) async {
      await openPage(
        tester,
        RecoveryKeyStatus(
          formatted: _formatted,
          keyCreatedAt: created,
          location: KeyLocation.synced,
        ),
      );
      expect(find.text(RecoveryKeyCopy.keptInICloud), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.keptOnDevice), findsNothing);
      expect(find.textContaining('refused'), findsNothing);
    });

    testWidgets('says this device only, with the keychain status when it '
        'refused', (tester) async {
      await openPage(
        tester,
        RecoveryKeyStatus(
          formatted: _formatted,
          keyCreatedAt: created,
          location: KeyLocation.thisDevice,
        ),
      );
      expect(find.text(RecoveryKeyCopy.keptOnDevice), findsOneWidget);
      expect(find.textContaining('refused'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await openPage(
        tester,
        RecoveryKeyStatus(
          formatted: _formatted,
          keyCreatedAt: created,
          location: KeyLocation.thisDevice,
          syncRefused: true,
          syncRefusalStatus: -34018,
        ),
      );
      expect(find.text(RecoveryKeyCopy.keptOnDevice), findsOneWidget);
      expect(
        find.text('iCloud Keychain refused it (status -34018).'),
        findsOneWidget,
      );
    });

    testWidgets('says nothing where the location is unknown', (tester) async {
      await openPage(
        tester,
        RecoveryKeyStatus(formatted: _formatted, keyCreatedAt: created),
      );
      expect(find.textContaining('Journal key kept'), findsNothing);
    });
  });

  group('the confirm step', () {
    Future<_FakeActions> openConfirm(
      WidgetTester tester, {
      bool fails = false,
    }) async {
      final _FakeActions actions = _FakeActions(fails: fails);
      await tester.pumpWidget(
        _app(
          <Override>[
            recoveryKeyStatusProvider.overrideWithValue(
              RecoveryKeyStatus(
                formatted: _formatted,
                keyCreatedAt: DateTime(2026, 11, 1),
              ),
            ),
            recoveryKeyActionsProvider.overrideWithValue(actions),
          ],
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(RecoveryKeyPage.route),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final String group in RecoveryKey.groupsOf(_formatted)) {
        expect(find.textContaining(group), findsWidgets);
      }
      await tester.tap(find.text(RecoveryKeyCopy.savedIt));
      await tester.pumpAndSettle();
      return actions;
    }

    testWidgets('refuses a group that is not the last', (tester) async {
      final _FakeActions actions = await openConfirm(tester);
      final List<String> groups = RecoveryKey.groupsOf(_formatted);
      await tester.enterText(
        find.byKey(RecoveryKeyPage.confirmField),
        groups.first == groups.last ? '0000' : groups.first,
      );
      await tester.tap(find.text(RecoveryKeyCopy.confirm));
      await tester.pumpAndSettle();
      expect(find.text(RecoveryKeyCopy.confirmWrong(8)), findsOneWidget);
      expect(actions.saved, 0);
      expect(find.byType(RecoveryKeyPage), findsOneWidget);
    });

    testWidgets('accepts the last group in lower case and closes', (
      tester,
    ) async {
      final _FakeActions actions = await openConfirm(tester);
      await tester.enterText(
        find.byKey(RecoveryKeyPage.confirmField),
        RecoveryKey.groupsOf(_formatted).last.toLowerCase(),
      );
      await tester.tap(find.text(RecoveryKeyCopy.confirm));
      await tester.pumpAndSettle();
      expect(actions.saved, 1);
      expect(find.byType(RecoveryKeyPage), findsNothing);
      expect(find.text(RecoveryKeyCopy.checked), findsOneWidget);
    });

    testWidgets('a failed save stays on the page and says so', (tester) async {
      await openConfirm(tester, fails: true);
      await tester.enterText(
        find.byKey(RecoveryKeyPage.confirmField),
        RecoveryKey.groupsOf(_formatted).last,
      );
      await tester.tap(find.text(RecoveryKeyCopy.confirm));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryKeyPage), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.saveFailed), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.checked), findsNothing);
    });

    testWidgets('Show the key again goes back to the groups', (tester) async {
      await openConfirm(tester);
      await tester.tap(find.text(RecoveryKeyCopy.showAgain));
      await tester.pumpAndSettle();
      expect(find.text(RecoveryKeyCopy.savedIt), findsOneWidget);
    });
  });

  group('waiting for iCloud Keychain', () {
    Future<void> pumpWaiting(
      WidgetTester tester, {
      required ProviderListenable<bool> awaiting,
    }) async {
      await tester.pumpWidget(
        _app(<Override>[
          journalNeedsRecoveryKeyProvider.overrideWithValue(true),
          journalKeyAwaitingSyncProvider.overrideWith(
            (ref) => ref.watch(awaiting),
          ),
          recoveryKeyActionsProvider.overrideWithValue(_FakeActions()),
          accountProvider.overrideWithValue(FakeAccount()),
        ], const Text('journal')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('with no key here, waits instead of asking for the key', (
      tester,
    ) async {
      await pumpWaiting(tester, awaiting: _waitingProvider);
      expect(find.text(RecoveryKeyCopy.waitingHeading), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.waitingBody), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.enterInstead), findsOneWidget);
      expect(find.byKey(RecoveryKeyEntryPage.field), findsNothing);
      expect(find.text('journal'), findsNothing);
    });

    testWidgets('says it is still waiting after two minutes', (tester) async {
      await pumpWaiting(tester, awaiting: _waitingProvider);
      await tester.pump(RecoveryKeyWaitingPage.slowAfter);
      expect(find.text(RecoveryKeyCopy.stillWaiting), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.waitingBody), findsNothing);
    });

    testWidgets('Enter recovery key instead opens the entry page', (
      tester,
    ) async {
      await pumpWaiting(tester, awaiting: _waitingProvider);
      await tester.tap(find.text(RecoveryKeyCopy.enterInstead));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(RecoveryKeyEntryPage.field), findsOneWidget);
    });

    testWidgets('a different key here goes straight to the entry page', (
      tester,
    ) async {
      final ProviderListenable<bool> notWaiting = Provider<bool>(
        (ref) => false,
      );
      await pumpWaiting(tester, awaiting: notWaiting);
      expect(find.byKey(RecoveryKeyEntryPage.field), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.waitingHeading), findsNothing);
    });

    testWidgets('the journal opens when the key arrives, with nothing typed', (
      tester,
    ) async {
      final _FakeActions actions = _FakeActions();
      await tester.pumpWidget(
        _app(<Override>[
          journalNeedsRecoveryKeyProvider.overrideWith(
            (ref) => ref.watch(_waitingProvider),
          ),
          journalKeyAwaitingSyncProvider.overrideWith(
            (ref) => ref.watch(_waitingProvider),
          ),
          recoveryKeyActionsProvider.overrideWithValue(actions),
        ], const Text('journal')),
      );
      await tester.pump();
      expect(find.text(RecoveryKeyCopy.waitingHeading), findsOneWidget);
      ProviderScope.containerOf(
        tester.element(find.text(RecoveryKeyCopy.waitingHeading)),
      ).read(_waitingProvider.notifier).arrive();
      await tester.pump();
      expect(find.text('journal'), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.waitingHeading), findsNothing);
      expect(actions.unlocks, isEmpty);
    });
  });

  group('recovery entry', () {
    Future<_FakeActions> pumpEntry(
      WidgetTester tester, {
      UnlockOutcome outcome = const UnlockOpened(),
      bool locked = true,
      bool fails = false,
      bool enabled = true,
      bool signedIn = true,
      FakeAccount? account,
    }) async {
      final _FakeActions actions = _FakeActions(outcome: outcome, fails: fails);
      await tester.pumpWidget(
        _app(
          <Override>[
            journalNeedsRecoveryKeyProvider.overrideWithValue(locked),
            recoveryKeyActionsProvider.overrideWithValue(actions),
            accountProvider.overrideWithValue(account ?? FakeAccount()),
          ],
          const Text('journal'),
          enabled: enabled,
          signedIn: signedIn,
        ),
      );
      await tester.pump();
      return actions;
    }

    Future<void> submit(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(RecoveryKeyEntryPage.field), text);
      await tester.tap(find.text(RecoveryKeyCopy.unlock));
      await tester.pumpAndSettle();
    }

    testWidgets('the gate opens straight through when no key is needed', (
      tester,
    ) async {
      await pumpEntry(tester, locked: false);
      expect(find.text('journal'), findsOneWidget);
      expect(find.byType(RecoveryKeyEntryPage), findsNothing);
    });

    testWidgets('the gate opens straight through while E2EE is off', (
      tester,
    ) async {
      await pumpEntry(tester, enabled: false);
      expect(find.text('journal'), findsOneWidget);
      expect(find.byType(RecoveryKeyEntryPage), findsNothing);
    });

    testWidgets('the gate leaves a signed-out user to the sign-in screens', (
      tester,
    ) async {
      await pumpEntry(tester, signedIn: false);
      expect(find.text('journal'), findsOneWidget);
      expect(find.byType(RecoveryKeyEntryPage), findsNothing);
    });

    testWidgets('the gate covers a route pushed before it locked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          <Override>[
            journalNeedsRecoveryKeyProvider.overrideWith(
              (ref) => ref.watch(_lockedProvider),
            ),
          ],
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/pushed'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed page'), findsOneWidget);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.text('pushed page')),
      );
      container.read(_lockedProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.text('pushed page'), findsNothing);
      expect(find.byType(RecoveryKeyEntryPage), findsOneWidget);
    });

    testWidgets('Sign out signs out, asking before it drops unsynced entries', (
      tester,
    ) async {
      final FakeAccount account = FakeAccount();
      account.respond = (call) async {
        if (call.fields['discardUnsynced'] == false) {
          throw const UnsyncedEntriesException();
        }
      };
      await pumpEntry(tester, account: account);
      await tester.tap(find.text(RecoveryKeyCopy.signOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AccountCopy.signOutAnyway));
      await tester.pumpAndSettle();
      expect(
        account.calls.map((call) => call.fields['discardUnsynced']),
        <bool>[false, true],
      );
    });

    testWidgets("I've lost my key explains, then starts a new journal", (
      tester,
    ) async {
      final _FakeActions actions = await pumpEntry(tester);
      await tester.tap(find.text(RecoveryKeyCopy.lostKey));
      await tester.pumpAndSettle();
      expect(find.text(RecoveryKeyCopy.lostBody), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.lostWayForward), findsOneWidget);
      expect(actions.newJournals, 0);
      await tester.tap(find.text(RecoveryKeyCopy.startNewJournal));
      await tester.pumpAndSettle();
      expect(actions.newJournals, 1);
      expect(find.byType(RecoveryKeyLostPage), findsNothing);
    });

    testWidgets('a new journal that fails stays on the page and says so', (
      tester,
    ) async {
      await pumpEntry(tester, fails: true);
      await tester.tap(find.text(RecoveryKeyCopy.lostKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(RecoveryKeyCopy.startNewJournal));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryKeyLostPage), findsOneWidget);
      expect(find.text(RecoveryKeyCopy.startNewFailed), findsOneWidget);
    });

    testWidgets("Keep looking goes back to the entry page", (tester) async {
      await pumpEntry(tester);
      await tester.tap(find.text(RecoveryKeyCopy.lostKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(RecoveryKeyCopy.keepLooking));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryKeyLostPage), findsNothing);
      expect(find.byKey(RecoveryKeyEntryPage.field), findsOneWidget);
    });

    testWidgets('rejects a bad checksum and says where', (tester) async {
      final _FakeActions actions = await pumpEntry(tester);
      expect(find.text('journal'), findsNothing);
      // Character 6 is the second of group 2.
      final String plain = _formatted.replaceAll('-', '');
      final String swapped = plain[5] == 'A' ? 'B' : 'A';
      final String typo = plain.replaceRange(5, 6, swapped);
      await submit(tester, typo);
      expect(find.text(RecoveryKeyCopy.typoAt(2, 2)), findsOneWidget);
      expect(actions.unlocks, isEmpty);
    });

    testWidgets('rejects a short key and a stray character', (tester) async {
      final _FakeActions actions = await pumpEntry(tester);
      await submit(tester, _formatted.substring(0, 20));
      expect(find.textContaining('this has'), findsOneWidget);
      await submit(tester, '${_formatted.substring(0, 38)}U');
      expect(
        find.text(RecoveryKeyCopy.badCharacter('U', 4, 8)),
        findsOneWidget,
      );
      expect(actions.unlocks, isEmpty);
    });

    testWidgets('passes a valid key on, spaces and case aside', (tester) async {
      final _FakeActions actions = await pumpEntry(tester);
      await submit(
        tester,
        RecoveryKey.groupsOf(_formatted).join(' ').toLowerCase(),
      );
      expect(actions.unlocks.single, _key);
      expect(
        tester
            .widget<TextField>(find.byKey(RecoveryKeyEntryPage.field))
            .decoration!
            .errorText,
        isNull,
      );
    });

    testWidgets('an unlock that throws leaves Unlock usable', (tester) async {
      final _FakeActions actions = await pumpEntry(tester, fails: true);
      await submit(tester, _formatted);
      expect(find.text(RecoveryKeyCopy.unlockFailed), findsOneWidget);
      await submit(tester, _formatted);
      expect(actions.unlocks, hasLength(2));
    });

    testWidgets('a key for another journal says so', (tester) async {
      await pumpEntry(tester, outcome: const UnlockNotThisJournal());
      await submit(tester, _formatted);
      expect(find.text(RecoveryKeyCopy.notThisJournal), findsOneWidget);
    });
  });
}
