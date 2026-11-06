import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/recovery_key.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/journal_key/recovery_key_screens.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/providers/today_provider.dart';

class _FakeToday extends Today {
  _FakeToday(this._start);

  final DateTime _start;

  @override
  DateTime build() => _start;
}

class _FakeActions implements RecoveryKeyActions {
  _FakeActions({this.outcome = const UnlockOpened()});

  final UnlockOutcome outcome;
  int saved = 0;
  int dismissed = 0;
  final List<Uint8List> unlocks = <Uint8List>[];

  @override
  Future<void> markSaved() async => saved++;

  @override
  Future<void> dismissCard() async => dismissed++;

  @override
  Future<UnlockOutcome> unlock(Uint8List recoveryKey) async {
    unlocks.add(recoveryKey);
    return outcome;
  }
}

final Uint8List _key = RecoveryKey.generate(Random(11));
final String _formatted = RecoveryKey.format(_key);

Widget _app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: appTheme(Brightness.light),
    routes: <String, WidgetBuilder>{
      RecoveryKeyPage.route: (_) => const RecoveryKeyPage(),
    },
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

    testWidgets('shows nothing while no key exists', (tester) async {
      await tester.pumpWidget(
        _app(<Override>[
          todayProvider.overrideWith(() => _FakeToday(DateTime(2030))),
        ], const Scaffold(body: RecoveryKeyCard())),
      );
      expect(find.text(RecoveryKeyCopy.cardTitle), findsNothing);
    });
  });

  group('the confirm step', () {
    Future<_FakeActions> openConfirm(WidgetTester tester) async {
      final _FakeActions actions = _FakeActions();
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

    testWidgets('Show the key again goes back to the groups', (tester) async {
      await openConfirm(tester);
      await tester.tap(find.text(RecoveryKeyCopy.showAgain));
      await tester.pumpAndSettle();
      expect(find.text(RecoveryKeyCopy.savedIt), findsOneWidget);
    });
  });

  group('recovery entry', () {
    Future<_FakeActions> pumpEntry(
      WidgetTester tester, {
      UnlockOutcome outcome = const UnlockOpened(),
      bool locked = true,
    }) async {
      final _FakeActions actions = _FakeActions(outcome: outcome);
      await tester.pumpWidget(
        _app(<Override>[
          journalNeedsRecoveryKeyProvider.overrideWithValue(locked),
          recoveryKeyActionsProvider.overrideWithValue(actions),
        ], const RecoveryKeyGate(child: Text('journal'))),
      );
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
      expect(find.textContaining('"U"'), findsOneWidget);
      expect(actions.unlocks, isEmpty);
    });

    testWidgets('passes a valid key on, spaces and case aside', (tester) async {
      final _FakeActions actions = await pumpEntry(tester);
      await submit(
        tester,
        RecoveryKey.groupsOf(_formatted).join(' ').toLowerCase(),
      );
      expect(actions.unlocks.single, _key);
      expect(find.byType(InputDecorator), findsOneWidget);
    });

    testWidgets('a key for another journal says so', (tester) async {
      await pumpEntry(tester, outcome: const UnlockNotThisJournal());
      await submit(tester, _formatted);
      expect(find.text(RecoveryKeyCopy.notThisJournal), findsOneWidget);
    });
  });
}
