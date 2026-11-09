import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/dial_layout.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/last_night_line.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/settle_write.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'last_night_fakes.dart';

const HabitMark _mark = HabitMark(0);

Finder _button(String tooltip) => find.byTooltip(tooltip);

bool _enabled(WidgetTester tester, String tooltip) =>
    tester
        .widget<IconButton>(
          find.ancestor(
            of: _button(tooltip),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed !=
    null;

// Each habit's total as its tally row shows it, by name.
Map<String, num?> _tallies(WidgetTester tester) => <String, num?>{
  for (final TallyRow row in tester.widgetList<TallyRow>(find.byType(TallyRow)))
    row.vice.name: row.total,
};

String? _summary(WidgetTester tester) =>
    tester.widget<DayDial>(find.byType(DayDial)).semanticsLabel;

// WCAG 2.x contrast ratio.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

Vice _habit(String id, {Unit unit = Unit.drink, bool archived = false}) => Vice(
  id: id,
  name: id,
  unit: unit,
  ownerID: ownerID,
  createdAt: fakeVice(id).createdAt,
  archived: archived,
);

List<Override> _today(
  List<Vice> vices,
  List<ViceActivity> Function(DateTime day) activities, {
  FakeTrackerWrites? writes,
  bool offline = false,
}) => <Override>[
  ...habitOverrides(vices),
  userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
  offlineProvider.overrideWith((ref) => Stream.value(offline)),
  trackerWritesProvider.overrideWithValue(writes ?? FakeTrackerWrites()),
  memoryJournal(),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => AsyncData(activities(day)),
  ),
];

// Tall enough that every tally sits above the Trends peek.
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = Size(
    tester.view.physicalSize.width,
    1000 * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpApp(
  WidgetTester tester,
  List<Override> overrides,
  Widget home, {
  RouteFactory? onGenerateRoute,
}) async {
  _useTallView(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        // The app's root watches the user, as here, before any write.
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            ref.watch(userProvider);
            return Scaffold(body: home);
          },
        ),
        onGenerateRoute: onGenerateRoute,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  final DateTime today = startOfDay(DateTime.now());

  group('day navigation', () {
    final Vice coffee = fakeVice('coffee');
    final List<Vice> vices = [coffee, fakeVice('beer'), fakeVice('cigarettes')];
    late List<DateTime> requestedDays;

    setUp(() {
      requestedDays = <DateTime>[];
    });

    List<Override> overrides({
      Map<String, double> storedTypicals = const <String, double>{},
    }) => [
      ...habitOverrides(vices, storedTypicals: storedTypicals),
      viceActivityDayProvider.overrideWith((ref, DateTime day) {
        requestedDays.add(day);
        final int daysAgo = daysBetween(day, today);

        if (daysAgo == 2) {
          return const AsyncLoading();
        }

        return AsyncData([
          fakeActivity(
            coffee.id,
            daysAgo + 1,
            day.add(const Duration(hours: 9)),
          ),
        ]);
      }),
    ];

    testWidgets('the dial sizes beads against the stored typicals', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      expect(
        tester.widget<DayDial>(find.byType(DayDial)).storedTypicals,
        isEmpty,
      );

      await _pumpApp(
        tester,
        overrides(storedTypicals: <String, double>{coffee.id: 3}),
        const ViceTracker(),
      );
      expect(
        tester.widget<DayDial>(find.byType(DayDial)).storedTypicals,
        <String, double>{coffee.id: 3},
      );
    });

    testWidgets('arrows change the day; there is no day after today', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      expect(find.text('Today'), findsOneWidget);
      expect(_tallies(tester)['coffee'], 1);
      expect(_enabled(tester, 'Next day'), isFalse);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(_tallies(tester)['coffee'], 2);
      expect(_enabled(tester, 'Previous day'), isTrue);
      expect(_enabled(tester, 'Next day'), isTrue);

      await tester.tap(_button('Next day'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(_tallies(tester)['coffee'], 1);
      // An auto-dispose day may be re-requested on return; how soon it is
      // disposed is Riverpod's scheduling, not this widget's.
      expect(requestedDays.toSet(), {today, addDays(today, -1)});
      await tester.pumpAndSettle();
    });

    Opacity labelOpacity(WidgetTester tester, String word) =>
        tester.widget<Opacity>(
          find
              .ancestor(of: find.text(word), matching: find.byType(Opacity))
              .first,
        );
    Offset labelShift(WidgetTester tester, String word) => Offset(
      tester
          .widget<Transform>(
            find
                .ancestor(of: find.text(word), matching: find.byType(Transform))
                .first,
          )
          .transform
          .getTranslation()
          .x,
      0,
    );

    testWidgets('last night\'s line shows on today alone', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, <Override>[
        ...overrides(),
        ...lastNightLineOverrides(
          const LastNight(
            sleepingHeartRate: NightCompare(
              value: 57,
              usual: 54,
              low: 53,
              high: 55,
            ),
          ),
        ),
      ], const ViceTracker());
      await tester.pump();
      expect(find.byType(LastNightLine), findsOneWidget);
      expect(
        find.textContaining('3 bpm above your usual', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LastNightLine), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('the day label slides in from the side of the new day', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      expect(labelOpacity(tester, 'Today').opacity, 1);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump(DialMotion.tallyRoll ~/ 3);
      expect(labelOpacity(tester, 'Yesterday').opacity, inExclusiveRange(0, 1));
      expect(labelShift(tester, 'Yesterday').dx, lessThan(0));

      await tester.pump(DialMotion.tallyRoll);
      expect(labelOpacity(tester, 'Yesterday').opacity, 1);
      expect(labelShift(tester, 'Yesterday').dx, 0);

      await tester.tap(_button('Next day'));
      await tester.pump();
      await tester.pump(DialMotion.tallyRoll ~/ 3);
      expect(labelShift(tester, 'Today').dx, greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets("the sweep's trace fades once the hand has gone round", (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      await tester.pumpAndSettle();
      ({double turn, double alpha})? trace() =>
          (tester
                          .widget<CustomPaint>(
                            find.byWidgetPredicate(
                              (Widget w) =>
                                  w is CustomPaint &&
                                  w.painter.runtimeType.toString() ==
                                      '_HandPainter',
                            ),
                          )
                          .painter!
                      as dynamic)
                  .sweep
              as ({double turn, double alpha})?;
      expect(trace(), isNull);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump(DialMotion.dayContract);
      await tester.pump();
      await tester.pump(DialMotion.daySweep ~/ 2);
      expect(trace()!.alpha, 1);
      expect(trace()!.turn, inExclusiveRange(0, 1));

      await tester.pump(
        DialMotion.daySweep ~/ 2 + DialMotion.landingRipple ~/ 2,
      );
      expect(trace()!.turn, 1);
      expect(trace()!.alpha, inExclusiveRange(0, 1));

      await tester.pump(DialMotion.landingRipple);
      expect(trace(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('under reduce motion the day label changes in place', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: Scaffold(body: ViceTracker())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();
      expect(labelOpacity(tester, 'Yesterday').opacity, 1);
      expect(labelShift(tester, 'Yesterday').dx, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('a day whose data never arrives does not freeze controls', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.tap(_button('Previous day'));
      await tester.pump();

      final DateTime twoAgo = addDays(today, -2);
      expect(find.text(dayWord(twoAgo, today)), findsOneWidget);
      expect(_tallies(tester)['coffee'], isNull);
      expect(_summary(tester), isNull);
      expect(_enabled(tester, 'Previous day'), isTrue);
      expect(_enabled(tester, 'Next day'), isTrue);

      await tester.tap(_button('Next day'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(_tallies(tester)['coffee'], 2);
      await tester.pumpAndSettle();
    });

    testWidgets('goes back further than a month', (WidgetTester tester) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      for (int i = 0; i < 40; i++) {
        await tester.tap(_button('Previous day'));
        await tester.pump();
      }

      expect(_tallies(tester)['coffee'], 41);
      expect(_enabled(tester, 'Previous day'), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('the date pill opens a calendar that picks the day', (
      WidgetTester tester,
    ) async {
      final DateTime target = today.day > 1 ? addDays(today, -1) : today;
      await _pumpApp(tester, [
        ...overrides(),
        viceActivityMonthProvider.overrideWith(
          (ref, DateTime month) =>
              AsyncData([fakeActivity(coffee.id, 1, target)]),
        ),
      ], const ViceTracker());

      await tester.tap(_button(DayPicker.chooseDay));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarSheet), findsOneWidget);
      expect(find.text(formatMonth(today)), findsOneWidget);
      expect(find.text(CalendarSheet.dialFootnote), findsOneWidget);
      expect(_enabled(tester, 'Next month'), isFalse);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('${formatDay(target)}, coffee'));
      await tester.pumpAndSettle();
      semantics.dispose();

      expect(find.byType(CalendarSheet), findsNothing);
      expect(find.text(dayWord(target, today)), findsOneWidget);
    });

    test('the calendar dots a day once for each habit logged on it', () {
      final DateTime day = DateTime(2026, 11, 3, 9);
      final Map<int, List<Vice>> logged = CalendarSheet.loggedByDay(vices, [
        fakeActivity('beer', 1, day),
        fakeActivity(coffee.id, 1, day),
        fakeActivity(coffee.id, 2, day.add(const Duration(hours: 2))),
        fakeActivity('gone', 1, day),
      ]);
      expect(logged.keys, [3]);
      expect(logged[3]!.map((Vice v) => v.id), ['coffee', 'beer']);
    });

    testWidgets('a sideways swipe on the dial changes the day', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.drag(find.byType(DayDial), const Offset(120, 0));
      await tester.pump();
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.drag(find.byType(DayDial), const Offset(-120, 0));
      await tester.pump();
      await tester.pump();
      expect(find.text('Today'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('the dial', () {
    final Vice coffee = _habit('Coffee');
    final Vice tea = _habit('Tea', unit: Unit.time);
    final Vice old = _habit('Sugar', unit: Unit.item, archived: true);

    testWidgets("a pending bead's rim keeps turning without rebuilding the "
        'dial', (WidgetTester tester) async {
      await _pumpApp(
        tester,
        _today(
          [coffee],
          (DateTime day) => [
            ViceActivity(
              id: 'queued',
              viceID: coffee.id,
              quantity: 1,
              ownerID: ownerID,
              createdAt: Timestamp.fromDate(
                today.add(const Duration(hours: 1)),
              ),
              pending: true,
            ),
          ],
        ),
        const ViceTracker(),
      );
      // Past the day's sweep and the bead's spring.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 16));

      CustomPainter beads() => tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is CustomPaint &&
                  w.painter.runtimeType.toString() == '_BeadsPainter',
            ),
          )
          .painter!;
      final CustomPainter before = beads();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.binding.hasScheduledFrame, isTrue);
      }
      expect(identical(beads(), before), isTrue);
    });

    testWidgets('is one node saying the day, each total and the first and '
        'last entry', (WidgetTester tester) async {
      final DateTime first = today.add(const Duration(hours: 8, minutes: 5));
      final DateTime last = today.add(const Duration(hours: 20, minutes: 50));
      await _pumpApp(
        tester,
        _today(
          [coffee, tea, old],
          (DateTime day) => [
            fakeActivity(coffee.id, 2, first),
            fakeActivity(old.id, 4, today.add(const Duration(hours: 9))),
            fakeActivity(coffee.id, 1, last),
          ],
        ),
        const ViceTracker(),
      );

      String time(DateTime t) => formatTime(t, alwaysUse24HourFormat: false);
      expect(
        _summary(tester),
        'Today, ${dayPillDate(today, today)}. Coffee 3 drinks, Tea 0 times. '
        'First entry ${time(first)}, last ${time(last)}.',
      );
      // The archived habit's entry is neither drawn nor counted.
      expect(find.text('2 entries'), findsOneWidget);
      expect(_tallies(tester).keys, ['Coffee', 'Tea']);
      await tester.pumpAndSettle();
    });

    testWidgets('a clear day says nothing was recorded', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today([coffee], (_) => const <ViceActivity>[]),
        const ViceTracker(),
      );

      expect(_summary(tester), endsWith('Coffee 0 drinks. Nothing recorded.'));
      await tester.pumpAndSettle();
    });

    testWidgets('each bead is a button that opens its entry', (
      WidgetTester tester,
    ) async {
      final ViceActivity entry = fakeActivity(
        coffee.id,
        2,
        today.add(const Duration(hours: 8)),
      );
      final List<String?> pushed = <String?>[];
      await _pumpApp(
        tester,
        _today([coffee], (_) => [entry]),
        const ViceTracker(),
        onGenerateRoute: (RouteSettings settings) {
          pushed.add(settings.name);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      );
      await tester.pumpAndSettle();
      final SemanticsHandle semantics = tester.ensureSemantics();

      final String label = DayDial.beadLabel(
        DialEntry(
          id: entry.id,
          vice: coffee,
          mark: _mark,
          quantity: 2,
          at: entry.createdAt.toDate(),
        ),
        alwaysUse24Hour: false,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        matchesSemantics(label: label, isButton: true, hasTapAction: true),
      );
      semantics.dispose();

      await tester.tap(find.byKey(ValueKey<String>('bead-${entry.id}')));
      await tester.pumpAndSettle();
      expect(pushed, ['/vices/${coffee.id}/activities/${entry.id}']);
    });

    // 30 Coffee entries from 08:00 two minutes apart, 19 Tea from 10:00 three
    // apart and one Coffee at 14:00: 50 in all, over the merge threshold.
    List<ViceActivity> dense(DateTime day, {int coffeeAtEight = 30}) =>
        <ViceActivity>[
          for (int i = 0; i < coffeeAtEight; i++)
            fakeActivity(coffee.id, 1, day.add(Duration(minutes: 480 + 2 * i))),
          for (int i = 0; i < 19; i++)
            fakeActivity(tea.id, 1, day.add(Duration(minutes: 600 + 3 * i))),
          fakeActivity(coffee.id, 2, day.add(const Duration(hours: 14))),
        ];

    testWidgets('a tap on one of two adjacent arcs opens an entry of its own '
        'hour', (WidgetTester tester) async {
      final List<String?> pushed = <String?>[];
      await _pumpApp(
        tester,
        _today(
          [coffee, tea],
          (DateTime day) => <ViceActivity>[
            ...dense(day),
            for (int i = 0; i < 3; i++)
              fakeActivity(tea.id, 2, day.add(Duration(minutes: 540 + 20 * i))),
          ],
        ),
        const ViceTracker(),
        onGenerateRoute: (RouteSettings settings) {
          pushed.add(settings.name);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('arc-9')), findsOneWidget);

      final Rect dial = tester.getRect(find.byType(DayDial));
      final double scale = dial.shortestSide / DialFace.side;
      await tester.tapAt(
        dial.center + dialPoint(dialAngle(541), HourArc.track) * scale,
      );
      await tester.pumpAndSettle();
      final ViceActivity nine = fakeActivity(
        tea.id,
        2,
        today.add(const Duration(minutes: 540)),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      // Late in 08's arc, whose neighbour is a quarter of an hour away.
      await tester.tapAt(
        dial.center + dialPoint(dialAngle(530), HourArc.track) * scale,
      );
      await tester.pumpAndSettle();
      final ViceActivity late = fakeActivity(
        coffee.id,
        1,
        today.add(const Duration(minutes: 530)),
      );
      expect(pushed, [
        '/vices/${tea.id}/activities/${nine.id}',
        '/vices/${coffee.id}/activities/${late.id}',
      ]);
    });

    testWidgets('above 48 entries a dense hour is one arc, and the dial still '
        'says every entry', (WidgetTester tester) async {
      await _pumpApp(
        tester,
        _today([coffee, tea, old], (DateTime day) => dense(day)),
        const ViceTracker(),
      );
      await tester.pumpAndSettle();
      final SemanticsHandle semantics = tester.ensureSemantics();

      expect(find.byKey(const ValueKey<String>('arc-8')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('arc-10')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('arc-14')), findsNothing);
      final ViceActivity lone = fakeActivity(
        coffee.id,
        2,
        today.add(const Duration(hours: 14)),
      );
      expect(find.byKey(ValueKey<String>('bead-${lone.id}')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('bead-'),
        ),
        findsOneWidget,
      );

      String time(int h) => formatTime(
        today.add(Duration(hours: h)),
        alwaysUse24HourFormat: false,
      );
      expect(
        find.bySemanticsLabel(
          '30 entries from ${time(8)} to ${time(9)}: Coffee 30 drinks',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '19 entries from ${time(10)} to ${time(11)}: Tea 19 times',
        ),
        findsOneWidget,
      );
      expect(
        _summary(tester),
        'Today, ${dayPillDate(today, today)}. Coffee 32 drinks, Tea 19 times. '
        'First entry ${time(8)}, last ${time(14)}.',
      );
      expect(find.text('50 entries'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('at 48 entries every entry is still a bead', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today([coffee, tea], (DateTime day) => dense(day, coffeeAtEight: 28)),
        const ViceTracker(),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('arc-8')), findsNothing);
      expect(find.text('48 entries'), findsOneWidget);
    });

    testWidgets('a tap on an arc opens the entry nearest the time tapped', (
      WidgetTester tester,
    ) async {
      final List<String?> pushed = <String?>[];
      await _pumpApp(
        tester,
        _today([coffee, tea], (DateTime day) => dense(day)),
        const ViceTracker(),
        onGenerateRoute: (RouteSettings settings) {
          pushed.add(settings.name);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      );
      await tester.pumpAndSettle();

      final Rect dial = tester.getRect(find.byType(DayDial));
      final double scale = dial.shortestSide / DialFace.side;
      // 08:31 on the arc's middle line; the nearest entry is 08:30's.
      await tester.tapAt(
        dial.center + dialPoint(dialAngle(511), HourArc.track) * scale,
      );
      await tester.pumpAndSettle();
      final ViceActivity half = fakeActivity(
        coffee.id,
        1,
        today.add(const Duration(minutes: 510)),
      );
      expect(pushed, ['/vices/${coffee.id}/activities/${half.id}']);
    });

    testWidgets('a screen reader opens the latest entry from an arc, and any '
        'entry from its actions', (WidgetTester tester) async {
      final List<String?> pushed = <String?>[];
      await _pumpApp(
        tester,
        _today([coffee, tea], (DateTime day) => dense(day)),
        const ViceTracker(),
        onGenerateRoute: (RouteSettings settings) {
          pushed.add(settings.name);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      );
      await tester.pumpAndSettle();
      final SemanticsHandle semantics = tester.ensureSemantics();

      String time(int h) => formatTime(
        today.add(Duration(hours: h)),
        alwaysUse24HourFormat: false,
      );
      final FinderBase<SemanticsNode> arc = find.semantics.byLabel(
        '30 entries from ${time(8)} to ${time(9)}: Coffee 30 drinks',
      );
      final SemanticsData data = arc.evaluate().single.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hint, DayDial.arcHint);
      expect(data.customSemanticsActionIds, hasLength(30));

      tester.semantics.tap(arc);
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      final ViceActivity half = fakeActivity(
        coffee.id,
        1,
        today.add(const Duration(minutes: 510)),
      );
      tester.semantics.customAction(
        arc,
        CustomSemanticsAction(
          label: DayDial.beadLabel(
            DialEntry(
              id: half.id,
              vice: coffee,
              mark: _mark,
              quantity: 1,
              at: half.createdAt.toDate(),
            ),
            alwaysUse24Hour: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ViceActivity latest = fakeActivity(
        coffee.id,
        1,
        today.add(const Duration(minutes: 538)),
      );
      expect(pushed, [
        '/vices/${coffee.id}/activities/${latest.id}',
        '/vices/${coffee.id}/activities/${half.id}',
      ]);
      semantics.dispose();
    });

    testWidgets("shows today's clock in the hub, and a past day's weekday", (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today(
          [coffee],
          (DateTime day) => [
            fakeActivity(coffee.id, 1, day.add(const Duration(hours: 1))),
          ],
        ),
        const ViceTracker(),
      );
      expect(find.text(formatClock(DateTime.now())), findsOneWidget);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(formatWeekdayShort(addDays(today, -1))), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('under reduce motion, nothing sweeps or springs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _today(
            [coffee],
            (DateTime day) => [
              fakeActivity(coffee.id, 1, day.add(const Duration(hours: 1))),
            ],
          ),
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: Scaffold(body: ViceTracker())),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // A fade of 150 ms is all there is.
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets("under reduce motion, the old day's beads fade out over "
        '150 ms before the new day fades in', (WidgetTester tester) async {
      final DateTime today = DateUtils.dateOnly(DateTime.now());
      String id(DateTime day) =>
          fakeActivity(coffee.id, 1, day.add(const Duration(hours: 1))).id;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _today(
            [coffee],
            (DateTime day) => [
              fakeActivity(coffee.id, 1, day.add(const Duration(hours: 1))),
            ],
          ),
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: MaterialApp(home: Scaffold(body: ViceTracker())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder bead(DateTime day) =>
          find.byKey(ValueKey<String>('bead-${id(day)}'));
      expect(bead(today), findsOneWidget);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(bead(today), findsOneWidget);
      expect(bead(addDays(today, -1)), findsNothing);

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(bead(today), findsNothing);
      expect(bead(addDays(today, -1)), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('a drag too short to change the day', () {
    final Vice coffee = _habit('Coffee');

    double shift(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(DayDial),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .x;

    for (final bool reduced in <bool>[false, true]) {
      testWidgets(
        reduced
            ? 'jumps back at once under reduce motion'
            : 'eases the dial back over 220 ms',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: _today([coffee], (_) => const <ViceActivity>[]),
              child: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: const MaterialApp(home: Scaffold(body: ViceTracker())),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final TestGesture drag = await tester.startGesture(
            tester.getCenter(find.byType(DayDial)),
          );
          for (int i = 0; i < 8; i++) {
            await drag.moveBy(const Offset(5, 0));
            await tester.pump(const Duration(milliseconds: 16));
          }
          // A quarter of the drag past the slop.
          expect(shift(tester), greaterThan(4));
          await drag.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (reduced) {
            expect(shift(tester), 0);
          } else {
            expect(shift(tester), inExclusiveRange(0, 5));
          }
          await tester.pump(const Duration(milliseconds: 130));
          expect(shift(tester), 0);
          expect(find.text('Today'), findsOneWidget);
          await tester.pumpAndSettle();
        },
      );
    }
  });

  group('a day with nothing recorded', () {
    final List<Vice> vices = [fakeVice('coffee')];

    List<Override> overrides({bool offline = false}) =>
        _today(vices, (_) => const <ViceActivity>[], offline: offline);

    testWidgets('reads as a clear day, today and on past days', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      expect(find.text(ClearDay.headline), findsOneWidget);
      expect(find.text(ClearDay.subline(isToday: true)), findsOneWidget);

      await tester.tap(_button('Previous day'));
      await tester.pump();
      await tester.pump();

      expect(find.text(ClearDay.headline), findsOneWidget);
      expect(find.text(ClearDay.subline(isToday: false)), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('offline, says the device may not have the day rather than '
        'calling it clear', (WidgetTester tester) async {
      await _pumpApp(tester, overrides(offline: true), const ViceTracker());
      await tester.pump();

      expect(find.text(ClearDay.offlineHeadline), findsOneWidget);
      expect(find.text(ClearDay.offlineBody), findsOneWidget);
      expect(find.text(ClearDay.headline), findsNothing);
      await tester.pumpAndSettle();
    });

    for (final Brightness brightness in Brightness.values) {
      testWidgets('the clear-day copy is readable in the ${brightness.name} '
          'theme', (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides(),
            child: MaterialApp(
              theme: appTheme(brightness),
              home: const Scaffold(body: ViceTracker()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final ThemeData theme = appTheme(brightness);
        final DialColors colors = theme.extension<DialColors>()!;
        final HSLColor ring = HSLColor.fromColor(colors.clearInk);
        expect(ring.hue, inInclusiveRange(80, 160), reason: 'green hue');
        for (final String text in [
          ClearDay.headline,
          ClearDay.subline(isToday: true),
        ]) {
          final Color foreground = tester
              .widget<Text>(find.text(text))
              .style!
              .color!;
          expect(
            _contrast(foreground, theme.colorScheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: text,
          );
        }
        await tester.pumpAndSettle();
      });
    }
  });

  group('the tallies', () {
    final Vice coffee = _habit('Coffee');
    final Vice tea = _habit('Tea', unit: Unit.time);
    late FakeTrackerWrites writes;

    setUp(() {
      writes = FakeTrackerWrites();
    });

    List<Override> overrides() => _today(
      [coffee, tea],
      (DateTime day) => [
        fakeActivity(coffee.id, 2, day.add(const Duration(hours: 8))),
        fakeActivity(coffee.id, 1, day.add(const Duration(hours: 9))),
      ],
      writes: writes,
    );

    testWidgets("list every habit in order with the day's total, zeros in "
        'the muted colour', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpApp(tester, overrides(), const ViceTracker());

      expect(_tallies(tester), {'Coffee': 3, 'Tea': 0});
      expect(find.bySemanticsLabel('Coffee, 3 drinks'), findsOneWidget);
      expect(find.bySemanticsLabel('Tea, 0 times'), findsOneWidget);
      final Color muted = DialColors.of(
        tester.element(find.byType(ViceTracker)),
      ).muted;
      expect(tester.widget<Text>(find.text('Tea')).style?.color, muted);
      expect(
        tester.widget<Text>(find.text('Coffee')).style?.color,
        isNot(muted),
      );
      semantics.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('+ logs one now, says so, and Undo deletes that entry', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      final DateTime before = DateTime.now();
      await tester.tap(_button(logOneLabel(tea)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final Write write = writes.writes.single;
      expect(write.op, 'recordActivity');
      expect(write.fields['viceID'], tea.id);
      expect(write.fields['quantity'], defaultQuantity);
      expect(write.fields['ownerID'], ownerID);
      final DateTime at = write.fields['createdAt']! as DateTime;
      expect(at.difference(before).inSeconds.abs(), lessThan(5));
      expect(find.textContaining('Logged 1 time of Tea at'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(writes.writes.last, Write('deleteActivity', write.id));
      expect(find.text(removedMessage), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('Cmd-1 and Cmd-2 log one of the first and second habit', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      // Only two habits, so the third key logs nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        <(String, Object?, Object?)>[
          for (final Write w in writes.writes)
            (w.op, w.fields['viceID'], w.fields['quantity']),
        ],
        <(String, Object?, Object?)>[
          ('recordActivity', coffee.id, defaultQuantity),
          ('recordActivity', tea.id, defaultQuantity),
        ],
      );
      expect(find.textContaining('Logged 1 time of Tea at'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(writes.writes.last, Write('deleteActivity', writes.writes[1].id));
      await tester.pumpAndSettle();
    });

    testWidgets('holding Cmd-1 down logs one entry, not one per repeat', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
      for (int i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(writes.writes.single.fields['viceID'], coffee.id);
      await tester.pumpAndSettle();
    });

    testWidgets('a key on a past day logs now and shows today', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(tester.widget<DayDial>(find.byType(DayDial)).day, isNot(today));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(writes.writes.single.fields['viceID'], coffee.id);
      expect(tester.widget<DayDial>(find.byType(DayDial)).day, today);
      await tester.pumpAndSettle();
    });

    testWidgets('two taps are two entries', (WidgetTester tester) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();
      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();

      expect(writes.writes.map((Write w) => w.id).toSet(), hasLength(2));
      await tester.pumpAndSettle();
    });

    testWidgets('+ without the journal key logs nothing and says why', (
      WidgetTester tester,
    ) async {
      writes.canCreate = false;
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button(logOneLabel(tea)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(writes.writes, isEmpty);
      expect(find.text('Not logged. $noJournalKeyMessage'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a log that outlasts the timeout says it will sync', (
      WidgetTester tester,
    ) async {
      writes.respond = (_) => Future<void>.delayed(const Duration(minutes: 1));
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();
      expect(find.textContaining('Logged 1 drink of Coffee'), findsOneWidget);

      await tester.pump(writeTimeout);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(queuedMessage), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
    });

    testWidgets('on a past day, + logs now and turns to today', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      await tester.tap(_button('Previous day'));
      await tester.pump();
      expect(find.text('Yesterday'), findsOneWidget);

      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(
        startOfDay(writes.writes.single.fields['createdAt']! as DateTime),
        today,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a logged bead flies in from the + and lands on the dial, and '
        'leaving mid-flight leaves nothing behind', (
      WidgetTester tester,
    ) async {
      final StreamController<List<ViceActivity>> day =
          StreamController<List<ViceActivity>>.broadcast();
      addTearDown(day.close);
      // A live day, so the logged entry arrives as it would from Firestore.
      final ValueNotifier<bool> shown = ValueNotifier<bool>(true);
      addTearDown(shown.dispose);
      _useTallView(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...habitOverrides([coffee, tea]),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            offlineProvider.overrideWith((ref) => Stream.value(false)),
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(),
            viceActivityDayForUserProvider.overrideWith(
              (ref, key) => day.stream,
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                ref.watch(userProvider);
                return Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: shown,
                    builder: (_, bool on, _) =>
                        on ? const ViceTracker() : const SizedBox(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      day.add(const <ViceActivity>[]);
      await tester.pumpAndSettle();

      final List<ViceActivity> logged = <ViceActivity>[];
      Future<String> logAndArrive() async {
        // The last log's bar would cover the row.
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
            .removeCurrentSnackBar();
        await tester.pump();
        await tester.tap(_button(logOneLabel(tea)));
        await tester.pump();
        final Write write = writes.writes.last;
        logged.add(
          ViceActivity(
            id: write.id,
            viceID: tea.id,
            quantity: 1,
            ownerID: ownerID,
            createdAt: Timestamp.fromDate(
              write.fields['createdAt']! as DateTime,
            ),
          ),
        );
        day.add([...logged]);
        await tester.pump();
        await tester.pump();
        return write.id;
      }

      final Finder flight = find.byWidgetPredicate(
        (Widget w) => w.runtimeType.toString() == '_BeadFlight',
      );
      await logAndArrive();
      await tester.pump(const Duration(milliseconds: 250));
      expect(flight, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
      expect(flight, findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1 entry'), findsOneWidget);

      // Gone within the flight: the dial takes its flight with it.
      await logAndArrive();
      await tester.pump(const Duration(milliseconds: 100));
      expect(flight, findsOneWidget);
      shown.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(flight, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('a total that changes rolls to its new value', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int> count = ValueNotifier<int>(1);
      addTearDown(count.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: count,
              builder: (_, int total, _) => TallyRow(
                vice: coffee,
                mark: _mark,
                total: total,
                day: today,
                onLog: (_) {},
              ),
            ),
          ),
        ),
      );
      count.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-roll, the old number leaves as the new one arrives.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('the Log fan', () {
    late FakeTrackerWrites writes;

    setUp(() {
      writes = FakeTrackerWrites();
    });

    List<Vice> habits(int n) => <Vice>[
      for (int i = 0; i < n; i++)
        Vice(
          id: 'h$i',
          name: 'Habit $i',
          unit: Unit.drink,
          ownerID: ownerID,
          createdAt: fakeVice('h$i').createdAt,
          archived: false,
        ),
    ];

    Finder wedge(String id) => find.byKey(ValueKey<String>('fan-wedge-$id'));
    Finder label(String id, String text) =>
        find.descendant(of: wedge(id), matching: find.text(text));

    testWidgets('opens a wedge for each habit; a tap on one logs it now', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today(habits(5), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      await tester.tap(find.byType(LogButton));
      await tester.pumpAndSettle();
      for (int i = 0; i < 5; i++) {
        expect(wedge('h$i'), findsOneWidget);
      }
      expect(wedge('more'), findsNothing);

      await tester.tap(label('h2', 'Habit 2'));
      await tester.pumpAndSettle();

      expect(wedge('h2'), findsNothing);
      expect(writes.writes.single.fields['viceID'], 'h2');
      expect(writes.writes.single.fields['quantity'], defaultQuantity);
    });

    testWidgets("the reminder's Log something opens the record dialog", (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = ProviderContainer(
        overrides: _today(habits(3), (_) => const <ViceActivity>[]),
      );
      // Pressed before Today was built, as from a cold start or signed out.
      container.read(pendingNudgeLogProvider.notifier).request();
      _useTallView(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ViceTracker())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RecordNewActivityDialog>(
              find.byType(RecordNewActivityDialog),
            )
            .initialViceID,
        isNull,
      );
      expect(container.read(pendingNudgeLogProvider), isFalse);

      // A press while something is open over Today closes it first.
      container.read(pendingNudgeLogProvider.notifier).request();
      await tester.pumpAndSettle();
      expect(find.byType(RecordNewActivityDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a hold on a wedge opens the record dialog with its habit', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today(habits(3), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      await tester.tap(find.byType(LogButton));
      await tester.pumpAndSettle();
      await tester.longPress(label('h1', 'Habit 1'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<RecordNewActivityDialog>(
              find.byType(RecordNewActivityDialog),
            )
            .initialViceID,
        'h1',
      );
      expect(
        find.descendant(
          of: find.byType(RecordNewActivityDialog),
          matching: find.text('Habit 1'),
        ),
        findsOneWidget,
      );
      expect(writes.writes, isEmpty);
    });

    testWidgets('pressing the button and releasing on a wedge logs it', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today(habits(5), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      final Offset start = tester.getCenter(find.byType(LogButton));
      final TestGesture gesture = await tester.startGesture(start);
      await tester.pumpAndSettle();
      final Offset target = tester.getCenter(label('h0', 'Habit 0'));
      await gesture.moveTo(start + const Offset(0, -30));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(writes.writes.single.fields['viceID'], 'h0');
      expect(wedge('h0'), findsNothing);
    });

    testWidgets('past eight habits, the eighth wedge is More', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        _today(habits(10), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      await tester.tap(find.byType(LogButton));
      await tester.pumpAndSettle();
      expect(wedge('h6'), findsOneWidget);
      expect(wedge('h7'), findsNothing);

      await tester.tap(label('more', 'More'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RecordNewActivityDialog>(
              find.byType(RecordNewActivityDialog),
            )
            .initialViceID,
        isNull,
      );
    });

    testWidgets('works from a keyboard: Enter opens it, Tab and Enter log a '
        'wedge, Escape closes it', (WidgetTester tester) async {
      await _pumpApp(
        tester,
        _today(habits(3), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      Future<void> openFromKeyboard() async {
        Focus.of(
          tester.element(
            find.descendant(
              of: find.byType(LogButton),
              matching: find.byType(Listener),
            ),
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(wedge('h0'), findsOneWidget);
      }

      await openFromKeyboard();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(wedge('h0'), findsNothing);
      expect(writes.writes, isEmpty);

      await openFromKeyboard();
      // Clockwise from the top: the second Tab reaches the second habit.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(wedge('h1'), findsNothing);
      expect(writes.writes.single.fields['viceID'], 'h1');
    });

    testWidgets('offers each habit to a screen reader as an action on the '
        'button', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pumpApp(
        tester,
        _today(habits(2), (_) => const <ViceActivity>[], writes: writes),
        const ViceTracker(),
      );

      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(LogButton.label),
      );
      final List<String> actions = <String>[
        for (final int id in node.getSemanticsData().customSemanticsActionIds!)
          CustomSemanticsAction.getAction(id)!.label!,
      ];
      expect(actions, ['Log 1 drink of Habit 0', 'Log 1 drink of Habit 1']);
      semantics.dispose();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the recorded snackbar offers Undo for eight seconds and '
      'replaces an earlier one', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    final ScaffoldMessengerState messenger = tester.state(
      find.byType(ScaffoldMessenger),
    );
    final List<String> undone = <String>[];

    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: true,
      onUndo: () => undone.add('first'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: false,
      onUndo: () => undone.add('second'),
    );
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text(RecordNewActivityDialog.recordedMessage), findsNothing);
    expect(find.text(queuedMessage), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    expect(undone, ['second']);
    await tester.pumpAndSettle();

    RecordNewActivityDialog.showRecorded(
      messenger,
      synced: true,
      onUndo: () {},
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 6500));
    expect(find.text(RecordNewActivityDialog.recordedMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(RecordNewActivityDialog.recordedMessage), findsNothing);
  });

  group('an account with no vices', () {
    List<Override> overrides() => [
      userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
      viceListProvider.overrideWithValue(AsyncData(const <Vice>[])),
      unarchivedViceListProvider.overrideWithValue(const AsyncData(<Vice>[])),
    ];

    testWidgets('sees an empty state on the Today tab, not a spinner', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ViceTracker());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(InfoBox),
          matching: find.textContaining('No habits yet'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('can reach Add vice from Manage Data', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester, overrides(), const ManageData());
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('No habits yet'), findsOneWidget);
      expect(find.byTooltip('Add habit'), findsOneWidget);
    });
  });

  testWidgets('the day pill takes its colour from the theme', (
    WidgetTester tester,
  ) async {
    final ThemeData light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _today([fakeVice('coffee')], (_) => const <ViceActivity>[]),
        child: MaterialApp(
          theme: light,
          home: const Scaffold(body: ViceTracker()),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('Today').first).style?.color,
      light.colorScheme.onSurface,
    );
    await tester.pumpAndSettle();
  });
}
