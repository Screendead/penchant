import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/journal_key/recovery_key_state.dart';
import 'package:tracker/menu_bar/app_views.dart';
import 'package:tracker/menu_bar/menu_bar_popover.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/widgets/app_menu_bar.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/writes/log_one.dart';

import 'fake_writes.dart';
import 'fakes.dart';

final List<Vice> _habits = <Vice>[
  fakeVice('coffee', name: 'Coffee'),
  fakeVice('tea', name: 'Tea'),
];

Future<(FakeTrackerWrites, ProviderContainer)> _pump(
  WidgetTester tester, {
  bool signedIn = true,
  bool started = true,
  VoidCallback? openApp,
  bool keyPending = false,
  bool needsRecoveryKey = false,
}) async {
  final FakeTrackerWrites writes = FakeTrackerWrites();
  final List<Override> overrides = <Override>[
    ...habitOverrides(_habits),
    userProvider.overrideWith(
      (ref) => Stream.value(signedIn ? FakeUser(ownerID) : null),
    ),
    offlineProvider.overrideWith((ref) => Stream.value(false)),
    trackerWritesProvider.overrideWithValue(writes),
    memoryJournal(),
    e2eeEnabledProvider.overrideWithValue(true),
    journalKeyPendingProvider.overrideWithValue(keyPending),
    journalNeedsRecoveryKeyProvider.overrideWithValue(needsRecoveryKey),
    viceActivityDayProvider.overrideWith(
      (ref, DateTime day) => AsyncData([
        fakeActivity('tea', 2, day.add(const Duration(hours: 9))),
      ]),
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MenuBarPopover(
        started: ValueNotifier<bool>(started),
        openApp: openApp ?? () {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (
    writes,
    ProviderScope.containerOf(tester.element(find.byType(MenuBarPopover))),
  );
}

void main() {
  testWidgets("shows today's dial with every habit below it", (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(340, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);

    final DayDial dial = tester.widget<DayDial>(find.byType(DayDial));
    expect(dial.day, dial.today);
    expect(dial.entries, hasLength(1));
    expect(dial.onBeadTap, isNull);
    expect(
      <String>[
        for (final MenuBarHabitRow row in tester.widgetList<MenuBarHabitRow>(
          find.byType(MenuBarHabitRow),
        ))
          '${row.vice.name} ${row.total}',
      ],
      <String>['Coffee 0', 'Tea 2'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    "a click on a habit logs one now, and the row's + is Undo for five seconds",
    (WidgetTester tester) async {
      final (FakeTrackerWrites writes, _) = await _pump(tester);

      await tester.tap(find.text('Coffee'));
      await tester.pump();
      final Write write = writes.writes.single;
      expect(write.op, 'recordActivity');
      expect(write.fields['viceID'], 'coffee');
      expect(write.fields['quantity'], defaultQuantity);
      expect(find.byType(SnackBar), findsNothing);
      final Finder coffeeUndo = find.descendant(
        of: find.byKey(const ValueKey<String>('menu-bar-coffee')),
        matching: find.text('Undo'),
      );
      expect(coffeeUndo, findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 4900));
      expect(coffeeUndo, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Undo'), findsNothing);
      await tester.pumpAndSettle();
    },
  );

  testWidgets("Undo on the row deletes the entry the click wrote", (
    WidgetTester tester,
  ) async {
    final (FakeTrackerWrites writes, _) = await _pump(tester);

    await tester.tap(find.text('Tea'));
    await tester.pump();
    final String id = writes.writes.single.id;
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(writes.writes.last.op, 'deleteActivity');
    expect(writes.writes.last.id, id);
    expect(find.text('Undo'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('a second log of the habit restarts its Undo', (
    WidgetTester tester,
  ) async {
    final (FakeTrackerWrites writes, _) = await _pump(tester);

    await tester.tap(find.text('Tea'));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Tea'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(writes.writes.last.op, 'deleteActivity');
    expect(writes.writes.last.id, writes.writes[1].id);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'while open it takes the Log menu and Cmd-1 to Cmd-9, and gives them back',
    (WidgetTester tester) async {
      final (FakeTrackerWrites writes, ProviderContainer container) =
          await _pump(tester);
      final TodayLogTarget target = container.read(todayLogTargetProvider);
      expect(target.log, isNotNull);

      target.log!(_habits.last);
      await tester.pump();
      expect(writes.writes.single.fields['viceID'], 'tea');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('menu-bar-tea')),
          matching: find.text('Undo'),
        ),
        findsOneWidget,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(writes.writes.last.fields['viceID'], 'coffee');
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(target.log, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('the last log target registered wins until it leaves', () {
    final TodayLogTarget target = TodayLogTarget();
    final List<String> calls = <String>[];
    void today(Vice v) => calls.add('today ${v.name}');
    void popover(Vice v) => calls.add('popover ${v.name}');

    target.add(today);
    target.add(popover);
    target.log!(_habits.first);
    target.remove(popover);
    target.log!(_habits.first);
    target.remove(today);
    expect(target.log, isNull);
    expect(calls, <String>['popover Coffee', 'today Coffee']);
  });

  testWidgets('signed out, it says to sign in and offers the app', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    await _pump(tester, signedIn: false, openApp: () => opened++);

    expect(find.text(MenuBarPopover.signedOut), findsOneWidget);
    expect(find.byType(DayDial), findsNothing);
    await tester.tap(find.text(MenuBarPopover.openLabel));
    expect(opened, 1);
  });

  for (final (String state, bool pending, bool locked)
      in <(String, bool, bool)>[
        ('loads', true, false),
        ('needs the recovery key', false, true),
      ]) {
    testWidgets(
      'while the journal key $state it lists no habit and logs nothing',
      (WidgetTester tester) async {
        final (FakeTrackerWrites writes, ProviderContainer container) =
            await _pump(tester, keyPending: pending, needsRecoveryKey: locked);

        expect(find.byType(MenuBarHabitRow), findsNothing);
        expect(find.byType(DayDial), findsNothing);
        expect(find.text('Coffee'), findsNothing);
        expect(
          find.text(MenuBarPopover.needsRecoveryKey),
          locked ? findsOneWidget : findsNothing,
        );
        expect(find.text(MenuBarPopover.openLabel), findsOneWidget);
        expect(container.read(todayLogTargetProvider).log, isNull);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(writes.writes, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('before Firebase starts it waits', (WidgetTester tester) async {
    await _pump(tester, started: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DayDial), findsNothing);
  });

  testWidgets('the main window shows the app; no popover is open', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const AppViews(
        main: Text('main', textDirection: TextDirection.ltr),
        popover: Text('popover', textDirection: TextDirection.ltr),
      ),
      wrapWithView: false,
    );
    expect(find.text('main'), findsOneWidget);
    expect(find.text('popover'), findsNothing);
  });
}
