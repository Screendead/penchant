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
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/manage_data.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';
import 'package:tracker/widgets/day_picker.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/log_fan.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/tally_row.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/settle_write.dart';

import 'fake_writes.dart';
import 'fakes.dart';

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
Map<String, int?> _tallies(WidgetTester tester) => <String, int?>{
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

    List<Override> overrides() => [
      ...habitOverrides(vices),
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
      expect(find.text(CalendarSheet.footnote), findsOneWidget);
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

    testWidgets('two taps are two entries', (WidgetTester tester) async {
      await _pumpApp(tester, overrides(), const ViceTracker());

      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();
      await tester.tap(_button(logOneLabel(coffee)));
      await tester.pump();

      expect(writes.writes.map((Write w) => w.id).toSet(), hasLength(2));
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
