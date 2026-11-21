import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/check_in_urges.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/widgets/after_event_card.dart';
import 'package:tracker/widgets/check_in_urges_card.dart';
import 'package:tracker/widgets/habit_follows_card.dart';
import 'package:tracker/widgets/trigger_amounts_card.dart';

import 'fakes.dart';
import 'insights_harness.dart';

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  // Tall enough that the list builds every card.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        home: const InsightsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<InsightsReport> _nothing(InsightsInput _) async =>
    const InsightsReport(findings: <HabitFinding>[], refused: <HabitRefusal>[]);

void _connected() => SharedPreferences.setMockInitialValues(<String, Object>{
  healthConnectedKey: true,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'Health is asked for only when Connect is tapped, and the journal is '
    'read only once Health has values',
    (WidgetTester tester) async {
      final FakeHealthSource health = FakeHealthSource(
        read: HealthValues(insightsJournal().health),
      );
      int opened = 0;
      await _pump(
        tester,
        insightsOverrides(
          health: health,
          runner: _nothing,
          onJournalOpened: () => opened++,
        ),
      );

      expect(find.text(InsightsPage.connectLabel), findsOneWidget);
      expect(find.text(InsightsPage.costsHeading), findsNothing);
      expect(health.authorizationRequests, 0);
      expect(health.reads, 0);
      expect(opened, 0);

      await tester.tap(find.text(InsightsPage.connectLabel));
      await tester.pumpAndSettle();

      expect(health.authorizationRequests, 1);
      expect(health.reads, greaterThan(0));
      expect(find.text(InsightsPage.connectLabel), findsNothing);
      expect(opened, greaterThan(0));
      expect(find.text(InsightsPage.costsHeading), findsOneWidget);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(healthConnectedKey), isTrue);
    },
  );

  testWidgets('connected with nothing in Health reads as no data, not zero', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: const HealthValues(<DailyOutcome>[])),
      ),
    );

    expect(find.text(InsightsPage.noHealthData), findsOneWidget);
    expect(find.text(InsightsPage.refusedHeading), findsNothing);
    expect(find.textContaining(RegExp(r'\b0\b')), findsNothing);
  });

  testWidgets('no Health data allows for access not being granted', (
    WidgetTester tester,
  ) async {
    _connected();
    final FakeHealthSource health = FakeHealthSource(
      read: const HealthValues(<DailyOutcome>[]),
    );
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text('Connected'), findsNothing);
    expect(find.text(InsightsPage.noHealthDataValue), findsOneWidget);
    expect(find.textContaining('Data Access & Devices'), findsOneWidget);
    final int reads = health.reads;

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(health.reads, reads + insightsHealthCalls);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(health.reads, reads + 2 * insightsHealthCalls);
  });

  testWidgets('a result that is not a finding, or names a habit the page '
      'does not list, gets no card', (WidgetTester tester) async {
    _connected();
    HabitFollows pair(String lead, String follower, FollowsVerdict verdict) =>
        HabitFollows(
          leadId: lead,
          followerId: follower,
          days: 61,
          followedDays: 40,
          uses: 84,
          share: 0.62,
          chance: 0.18,
          pValue: 0.0001,
          verdict: verdict,
        );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        runner: (_) async => InsightsReport(
          findings: const <HabitFinding>[],
          refused: const <HabitRefusal>[],
          follows: <HabitFollows>[
            pair('coffee', 'tea', FollowsVerdict.chance),
            pair('water', 'tea', FollowsVerdict.tooFewDays),
            pair('gone', 'coffee', FollowsVerdict.found),
            pair('tea', 'gone', FollowsVerdict.found),
          ],
          triggers: const <HabitTriggers>[
            HabitTriggers(
              habitId: 'coffee',
              entries: 120,
              tagged: 64,
              triggers: <TriggerAmount>[
                TriggerAmount(
                  trigger: 'work',
                  entries: 30,
                  withDays: 18,
                  withoutDays: 25,
                  withMean: 2.9,
                  withoutMean: 2,
                  pValue: 0.001,
                  verdict: TriggerVerdict.tooSmall,
                ),
              ],
            ),
          ],
          checkInUrges: const <CheckInUrge>[
            CheckInUrge(
              habitId: 'coffee',
              days: 18,
              entries: 41,
              checkIns: 37,
              noUrge: 15,
              entryMean: 3.6,
              checkInMean: 1.4,
              pValue: 0.0002,
              refusal: RefusalReason.withinNoise,
            ),
          ],
          calendarDays: const <CalendarDay>[
            CalendarDay(
              habitId: 'tea',
              feature: CalendarDayFeature.events,
              cut: 2,
              usableDays: 90,
              moreDays: 40,
              refusal: RefusalReason.withinNoise,
            ),
          ],
        ),
      ),
    );

    expect(find.byType(HabitFollowsCard), findsNothing);
    expect(find.byType(TriggerAmountsCard), findsNothing);
    expect(find.byType(CheckInUrgesCard), findsNothing);
    expect(find.byType(CalendarDayCardView), findsNothing);
    expect(find.text(InsightsPage.setsOffBody), findsOneWidget);
  });

  testWidgets('a habit list that fails to load shows an error with Retry', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncError<List<Vice>>(StateError('denied'), StackTrace.empty),
      ),
    );

    expect(find.text('Your habits couldn’t be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text(InsightsPage.loadingLabel), findsNothing);
  });

  testWidgets('a locked device says so and offers another try', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(
          failure: PlatformException(code: healthDatabaseInaccessible),
        ),
      ),
    );

    expect(find.text('Health is locked'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a journal that fails to load shows an error with Retry', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        activities: AsyncError<List<ViceActivity>>(
          StateError('offline'),
          StackTrace.empty,
        ),
      ),
    );

    expect(find.text('Your journal couldn’t be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  test('today\'s unfinished day metrics are left out; its night is kept', () {
    final DateTime yesterday = DateTime(2026, 11, 7);
    final InsightsInput input = InsightsInput.from(
      activities: const <ViceActivity>[],
      health: <DailyOutcome>[
        DailyOutcome(insightsToday, HealthMetric.stepCount.id, 2000),
        DailyOutcome(insightsToday, HealthMetric.restingHeartRate.id, 60),
        DailyOutcome(insightsToday, HealthMetric.sleepDeep.id, 70),
        DailyOutcome(yesterday, HealthMetric.stepCount.id, 8000),
      ],
      today: insightsToday.add(const Duration(hours: 9)),
    );
    expect(
      <(DateTime, String)>[
        for (final o in input.outcomes) (o.date, o.metricId),
      ],
      <(DateTime, String)>[
        (insightsToday, HealthMetric.sleepDeep.id),
        (yesterday, HealthMetric.stepCount.id),
      ],
    );
  });

  group('last night waits for no engine', () {
    const LastNight night = LastNight(
      sleepingHeartRate: NightCompare(value: 57, usual: 54, low: 53, high: 55),
    );

    testWidgets('it leads the page while the engine runs', (
      WidgetTester tester,
    ) async {
      _connected();
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final Completer<InsightsReport> never = Completer<InsightsReport>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: insightsOverrides(
            health: FakeHealthSource(
              read: HealthValues(insightsJournal().health),
            ),
            runner: (_) => never.future,
            activities: const AsyncData<List<ViceActivity>>(<ViceActivity>[]),
            lastNight: night,
          ),
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const InsightsPage(),
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(find.text(InsightsPage.loadingLabel), findsOneWidget);
      expect(find.text(InsightsPage.lastNightHeading), findsOneWidget);
      expect(find.text('usual 54 · 3 above'), findsOneWidget);
      expect(find.text('Nothing logged yesterday'), findsOneWidget);
    });

    testWidgets('and when the engine fails', (WidgetTester tester) async {
      _connected();
      await _pump(
        tester,
        insightsOverrides(
          health: FakeHealthSource(
            read: HealthValues(insightsJournal().health),
          ),
          runner: (_) async => throw StateError('engine'),
          lastNight: night,
        ),
      );

      expect(find.text('Insights couldn’t be worked out'), findsOneWidget);
      expect(find.text(InsightsPage.lastNightHeading), findsOneWidget);
      expect(find.text('usual 54 · 3 above'), findsOneWidget);
    });
  });

  group('last night notes', () {
    test('agree with the whole numbers shown', () {
      expect(
        lastNightHeartNote(
          const NightCompare(value: 56.6, usual: 54.4, low: 53, high: 55),
        ),
        'usual 54 · 3 above',
      );
      expect(
        lastNightSleepNote(
          const NightCompare(value: 409.6, usual: 435.4, low: 420, high: 450),
        ),
        'usual 7 h 15 m · 25 min under',
      );
      expect(
        lastNightHrvNote(
          const NightCompare(value: 44.4, usual: 48, low: 45, high: 51),
        ),
        'usual range 45–51 · below',
      );
    });

    test('a range whose ends round to one number is one number', () {
      expect(
        lastNightHrvNote(
          const NightCompare(value: 44.6, usual: 45.3, low: 45.2, high: 45.4),
        ),
        'usual 45 · in your usual range',
      );
    });
  });

  test('yesterday is the day before as the engine keys it, archived habits '
      'left out', () {
    final DateTime yesterday = addDays(insightsToday, -1);
    final List<Vice> vices = <Vice>[
      ...insightsVices,
      fakeVice('wine', name: 'Wine', unit: Unit.drink),
      fakeVice('gin', name: 'Gin', unit: Unit.drink, archived: true),
    ];
    List<String> lines(List<ViceActivity> journal) => <String>[
      for (final YesterdayLine line in yesterdayLines(
        journal,
        vices,
        habitMarks(vices),
        insightsToday,
        alwaysUse24HourFormat: true,
      ))
        line.text,
    ];

    expect(
      lines(<ViceActivity>[
        fakeActivity('wine', 2, yesterday.add(const Duration(hours: 20))),
        // After midnight: still the evening before.
        fakeActivity('wine', 1, insightsToday.add(const Duration(hours: 1))),
        // The day before yesterday.
        fakeActivity('wine', 4, yesterday.subtract(const Duration(hours: 2))),
        fakeActivity('gin', 1, yesterday.add(const Duration(hours: 20))),
      ]),
      <String>['Yesterday: Wine 3 drinks, last at 01:00'],
    );
    expect(lines(const <ViceActivity>[]), <String>['Nothing logged yesterday']);
  });

  group('copy', () {
    HabitFinding finding(
      String metric,
      double effect,
      stats.Interval interval,
    ) => HabitFinding(
      habitId: 'coffee',
      metricId: metric,
      lagDays: 1,
      usableDays: 64,
      exposedDays: 22,
      raw: null,
      effect: effect,
      interval: interval,
      standardized: 1,
      pValue: 0.001,
    );

    test('a range close to zero keeps enough digits not to read as zero', () {
      final HabitFinding f = finding(
        HealthMetric.sleepDeep.id,
        3,
        const stats.Interval(0.2, 5.8),
      );
      expect(findingRange(f, 'en'), 'Range: 0.2 to 5.8 min more');
    });

    test('blood oxygen reads in percentage points', () {
      final HabitFinding f = finding(
        HealthMetric.oxygenSaturation.id,
        -0.004,
        const stats.Interval(-0.007, -0.001),
      );
      expect(
        findingSentence(f, 'Tea', 'en'),
        'On days after Tea, your blood oxygen averages 0.4 percentage points '
        'lower.',
      );
    });
  });
}
