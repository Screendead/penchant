import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/time_dial.dart';

import 'fake_writes.dart';
import 'fakes.dart';

final DateTime _now = DateTime(2026, 11, 5, 21, 10, 30);
final DateTime _today = DateTime(2026, 11, 5);

final Vice _coffee = Vice(
  id: 'coffee',
  name: 'Coffee',
  unit: Unit.drink,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  archived: false,
);

final ViceActivity _edited = fakeActivity(
  'coffee',
  3,
  DateTime(2026, 11, 5, 18, 30),
);
final ViceActivity _other = fakeActivity(
  'coffee',
  1,
  DateTime(2026, 11, 5, 7, 5),
);

EntryTimeController _time(WidgetTester tester) =>
    tester.widget<EntryTimeField>(find.byType(EntryTimeField)).controller;

// Where [minute] sits on the time dial, inside its rim.
Offset _at(WidgetTester tester, int minute) {
  final Rect dial = tester.getRect(find.byType(TimeDial));
  return dial.center +
      dialPoint(dialAngle(minute.toDouble()), dial.width * 0.35);
}

Future<void> _open(
  WidgetTester tester,
  FakeTrackerWrites writes, {
  Widget? page,
  List<Vice>? habits,
  List<ViceActivity>? todayEntries,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...habitOverrides(habits ?? <Vice>[_coffee]),
        trackerWritesProvider.overrideWithValue(writes),
        memoryJournal(),
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        viceActivityProvider.overrideWith(
          (ref, String id) => AsyncData(_edited),
        ),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => AsyncData(
            day == _today
                ? todayEntries ?? <ViceActivity>[_other, _edited]
                : const <ViceActivity>[],
          ),
        ),
        viceActivityMonthProvider.overrideWith(
          (ref, DateTime month) => const AsyncData(<ViceActivity>[]),
        ),
      ],
      child: MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              // Keeps the signed-in user resolved, as the app does.
              ref.watch(userProvider);
              return TextButton(
                onPressed: () => page == null
                    ? RecordNewActivityDialog.show(
                        context,
                        initialViceID: _coffee.id,
                      )
                    : Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => page)),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeTrackerWrites writes;

  setUp(() {
    writes = FakeTrackerWrites();
  });

  test('a step moves to the next or previous multiple of 5 minutes, within '
      'the day and the latest minute', () {
    expect(stepMinute(600, 1, latest: 1439), 605);
    expect(stepMinute(603, 1, latest: 1439), 605);
    expect(stepMinute(603, -1, latest: 1439), 600);
    expect(stepMinute(600, -1, latest: 1439), 595);
    expect(stepMinute(600, 12, latest: 1439), 660);
    expect(stepMinute(2, -1, latest: 1439), 0);
    expect(stepMinute(1435, 1, latest: 1439), 1439);
    expect(stepMinute(1268, 1, latest: 1270), 1270);
  });

  test('a point on the dial reads as its minute, snapped to 5', () {
    const double side = TimeDial.side;
    const Offset centre = Offset(side / 2, side / 2);
    expect(minuteAtPoint(centre + const Offset(0, -50), side), 0);
    expect(minuteAtPoint(centre + const Offset(50, 0), side), 360);
    expect(minuteAtPoint(centre + const Offset(0, 50), side), 720);
    expect(minuteAtPoint(centre + const Offset(-50, 0), side), 1080);
    expect(minuteAtPoint(centre + const Offset(-0.1, -50), side), 0);
    expect(minuteAtPoint(centre + dialPoint(dialAngle(487), 60), side), 485);
  });

  testWidgets('a new entry follows the clock and is logged at the moment it '
      'is saved, to the second', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      expect(_time(tester).followsClock, isTrue);
      expect(
        find.text('${EntryTimeField.nowLabel} · ${EntryTimeField.dragHint}'),
        findsOneWidget,
      );
      expect(find.text('Log 1 drink at 21:10'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();

      await tester.pump();

      await tester.ensureVisible(find.byKey(RecordNewActivityDialog.submitKey));

      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.fields['createdAt'], _now);
    });
  });

  testWidgets('a drag round the dial sets a time on the 5-minute grid, and '
      'never pulls the sheet down', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      final TestGesture drag = await tester.startGesture(_at(tester, 18 * 60));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 18));
      for (int i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 30));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();

      expect(find.byType(RecordNewActivityDialog), findsOneWidget);
      final DateTime at = _time(tester).at!;
      expect(at.isBefore(DateTime(2026, 11, 5, 18)), isTrue);
      expect(at.minute % TimeDial.step, 0);
      expect(find.textContaining('min ago'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();

      await tester.pump();

      await tester.ensureVisible(find.byKey(RecordNewActivityDialog.submitKey));

      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(RecordNewActivityDialog.submitKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.fields['createdAt'], at);
    });
  });

  testWidgets('on today a time after now goes back to following the clock, '
      'as Now does', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      await tester.tapAt(_at(tester, 6 * 60));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 6));
      expect(find.text('15 h 10 min ago'), findsOneWidget);

      await tester.tap(find.text(EntryTimeField.nowLabel));
      await tester.pump();
      expect(_time(tester).followsClock, isTrue);

      await tester.tapAt(_at(tester, 6 * 60));
      await tester.pump();
      await tester.tapAt(_at(tester, 23 * 60));
      await tester.pump();
      expect(_time(tester).followsClock, isTrue);
    });
  });

  testWidgets('a screen reader hears a slider whose actions step 5 minutes, '
      'never past now', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      expect(
        tester.getSemantics(find.byType(TimeDial)),
        matchesSemantics(
          isSlider: true,
          label: TimeDial.label,
          value: '21:10',
          decreasedValue: '21:05',
          hasDecreaseAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      tester.semantics.decrease(find.semantics.byLabel(TimeDial.label));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 21, 5));
      tester.semantics.increase(find.semantics.byLabel(TimeDial.label));
      await tester.pump();
      expect(_time(tester).followsClock, isTrue);
    });
    semantics.dispose();
  });

  testWidgets('arrow keys and page keys step the time once the dial has '
      'focus', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      await tester.tapAt(_at(tester, 12 * 60));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 12, 5));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 11, 55));
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 10, 55));
    });
  });

  testWidgets('the day under the dial opens the calendar, and the day picked '
      'keeps the time', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      await tester.tapAt(_at(tester, 20 * 60));
      await tester.pump();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text(CalendarSheet.logFootnote), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarSheet),
          matching: find.text('3'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_time(tester).at, DateTime(2026, 11, 3, 20));
      expect(find.text(EntryTimeField.nowLabel), findsNothing);
      // A past day's dial reaches its last minute.
      await tester.tapAt(_at(tester, 23 * 60));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 3, 23));
    });
  });

  test('a day ahead of the clock shows as its date, not a weekday word', () {
    expect(EntryTimeField.dayText(DateTime(2026, 11, 6), _today), 'Fri, Nov 6');
    expect(
      EntryTimeField.dayText(DateTime(2026, 11, 4), _today),
      'Yesterday, Wed, Nov 4',
    );
  });

  testWidgets('with a time set, the line under the dial follows the clock', (
    tester,
  ) async {
    DateTime now = _now;
    await withClock(Clock(() => now), () async {
      await _open(tester, writes);
      await tester.tapAt(_at(tester, 21 * 60 + 5));
      await tester.pump();
      expect(_time(tester).at, DateTime(2026, 11, 5, 21, 5));
      expect(find.text('5 min ago'), findsOneWidget);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('6 min ago'), findsOneWidget);
    });
  });

  testWidgets('the day reads to a screen reader as one button with its hint, '
      'and the separators say nothing', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await withClock(Clock.fixed(_now), () async {
      await _open(tester, writes);
      await tester.tapAt(_at(tester, 6 * 60));
      await tester.pump();
      expect(
        tester.getSemantics(find.text('Today')),
        matchesSemantics(
          label: 'Today',
          hint: EntryTimeField.chooseDay,
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
        ),
      );
      expect(find.semantics.byLabel(' · '), findsNothing);
    });
    semantics.dispose();
  });

  testWidgets('an archived habit\'s entries stay off the dial, as off Today', (
    tester,
  ) async {
    final Vice tea = fakeVice('tea', unit: Unit.drink, archived: true);
    final ViceActivity teaTime = fakeActivity(
      'tea',
      1,
      DateTime(2026, 11, 5, 16),
    );
    await withClock(Clock.fixed(_now), () async {
      await _open(
        tester,
        writes,
        habits: <Vice>[_coffee, tea],
        todayEntries: <ViceActivity>[_other, teaTime],
      );
      expect(
        tester.widget<TimeDial>(find.byType(TimeDial)).ghosts.map((g) => g.id),
        <String>[_other.id],
      );
    });
  });

  testWidgets('the editor fades the day\'s other entries, not its own, and '
      'saves a time moved on the dial', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(
        tester,
        writes,
        page: ViceActivityEditorPage(viceID: 'coffee', activityID: _edited.id),
      );
      expect(_time(tester).at, DateTime(2026, 11, 5, 18, 30));
      expect(
        tester.widget<TimeDial>(find.byType(TimeDial)).ghosts.map((g) => g.id),
        <String>[_other.id],
      );

      await tester.tapAt(_at(tester, 9 * 60));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.byKey(ViceActivityEditorPage.saveKey));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(ViceActivityEditorPage.saveKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.op, 'updateActivity');
      expect(writes.writes.single.fields, <String, Object?>{
        'createdAt': DateTime(2026, 11, 5, 9),
      });
    });
  });

  testWidgets('the editor writes no time the user left alone', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _open(
        tester,
        writes,
        page: ViceActivityEditorPage(viceID: 'coffee', activityID: _edited.id),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.byKey(ViceActivityEditorPage.saveKey));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(ViceActivityEditorPage.saveKey));
      await tester.pumpAndSettle();
      expect(writes.writes.single.fields, <String, Object?>{'quantity': 4});
    });
  });
}
