import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/daily_series.dart' show HabitUse;
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/insights_provider.dart';

import 'fakes.dart';
import 'insights/hours_after_synthetic.dart';
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

// The drill-in holds every card, the refusals and the settled Health card.
Future<void> _openCosts(WidgetTester tester) async {
  await tester.tap(find.text(InsightsPage.moreCosts));
  await tester.pumpAndSettle();
}

void _connected() => SharedPreferences.setMockInitialValues(<String, Object>{
  healthConnectedKey: true,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a habit with an effect gets a finding in plain words, and the '
      'others are listed with the reason', (WidgetTester tester) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
      ),
    );

    expect(find.text('Connected'), findsNothing);
    expect(find.text(InsightsPage.costsHeading), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(
          r'^On nights after Coffee, your deep sleep averages 1\d min '
          r'less\.$',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r'^Range: \d+ to \d+ min less$')),
      findsOneWidget,
    );
    expect(
      find.textContaining('On days after Coffee, your resting heart rate'),
      findsOneWidget,
    );
    expect(find.textContaining('after Tea'), findsNothing);
    expect(find.textContaining('after Water'), findsNothing);
    expect(find.text(InsightsPage.refusedHeading), findsNothing);

    await _openCosts(tester);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text(InsightsPage.manageLabel), findsOneWidget);
    expect(
      find.textContaining('On nights after Coffee, your deep sleep'),
      findsOneWidget,
    );
    expect(find.text(InsightsPage.refusedHeading), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Within the noise: no clear difference'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('Too few days yet'), findsOneWidget);
    // No heart rate readings, so nothing ran in the hours after a use.
    expect(find.text(InsightsPage.hoursAfterNote), findsNothing);
  });

  testWidgets('heart rate in the hours after a use reads in its own words', (
    WidgetTester tester,
  ) async {
    _connected();
    final Synthetic s = insightsHoursYear();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(
          read: HealthValues(insightsJournal().health),
          sampleData: <HealthSampleMetric, List<HealthSample>>{
            for (final HealthSampleMetric m in HealthSampleMetric.values)
              if (s.samples[m.id] case final List<HealthSample> list) m: list,
          },
        ),
        activities: AsyncData<List<ViceActivity>>(<ViceActivity>[
          for (final HabitUse u in s.uses) fakeActivity(u.habitId, 1, u.at),
        ]),
      ),
    );
    await _openCosts(tester);

    expect(
      find.textContaining(
        RegExp(
          r'^One to two hours after Coffee, your heart rate, set against the '
          r'hour before, averages \d bpm higher than at the same time after '
          r'waking without it\.$',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        RegExp(
          r'^From \d+ days with Coffee, against \d+ days at the same time '
          r'after waking with none of it within 4 hours$',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(InsightsPage.hoursAfterNote), findsOneWidget);
  });

  testWidgets('a habit that may be chance among many comparisons says so', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        runner: (_) async => const InsightsReport(
          findings: <HabitFinding>[],
          refused: <HabitRefusal>[
            HabitRefusal(
              habitId: 'tea',
              metricId: 'sleepDeep',
              lagDays: 1,
              usableDays: 120,
              exposedDays: 60,
              raw: null,
              reason: RefusalReason.chance,
              effect: -6,
              interval: stats.Interval(-11, -1),
              pValue: 0.03,
            ),
          ],
        ),
      ),
    );

    expect(find.text(InsightsPage.nothingClear), findsOneWidget);
    expect(find.text(InsightsPage.more(1)), findsNothing);
    await _openCosts(tester);
    expect(find.text('Tea'), findsOneWidget);
    expect(
      find.text('Could be chance: one of many comparisons'),
      findsOneWidget,
    );
  });

  testWidgets('an amount and a time of last use read in their own words, in '
      'the habit\'s unit, on one card', (WidgetTester tester) async {
    _connected();
    HabitFinding finding(InsightKind kind, double step, double effect) =>
        HabitFinding(
          habitId: 'coffee',
          metricId: 'sleepDeep',
          lagDays: 1,
          usableDays: 120,
          exposedDays: 120,
          raw: null,
          kind: kind,
          step: step,
          effect: effect,
          interval: stats.Interval(effect * 1.5, effect / 2),
          standardized: -0.5,
          pValue: 0.001,
        );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[
          fakeVice('coffee', name: 'Coffee', unit: Unit.drink),
        ]),
        runner: (_) async => InsightsReport(
          findings: <HabitFinding>[
            finding(InsightKind.dose, 1, -6),
            finding(InsightKind.lastUse, 60, -12),
          ],
          refused: const <HabitRefusal>[],
        ),
      ),
    );

    expect(find.text('Coffee · sleep'), findsOneWidget);
    expect(
      find.text(
        'On days your last use of Coffee is an hour later, your deep sleep '
        'that night averages 12 min less.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('More per extra drink: deep sleep 6 min less'),
      findsOneWidget,
    );
    expect(find.text('From 120 days with Coffee'), findsOneWidget);
    expect(find.text(InsightsPage.refusedHeading), findsNothing);

    // One card and nothing refused: the drill-in still holds Health's card.
    expect(find.text(InsightsPage.more(1)), findsNothing);
    await _openCosts(tester);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text(InsightsPage.manageLabel), findsOneWidget);
  });

  testWidgets('a time of last use on sleep shows its whole effect, then the '
      'part at the same bedtime, then what that size has been shown to do', (
    WidgetTester tester,
  ) async {
    _connected();
    HabitFinding finding(
      InsightKind kind,
      double step,
      double effect, {
      HabitInsight? sameBedtime,
    }) => HabitFinding(
      habitId: 'coffee',
      metricId: 'sleepREM',
      lagDays: 1,
      usableDays: 120,
      exposedDays: 120,
      raw: null,
      kind: kind,
      step: step,
      effect: effect,
      interval: stats.Interval(effect * 1.5, effect / 2),
      standardized: -0.5,
      pValue: 0.001,
      sameBedtime: sameBedtime,
    );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[
          fakeVice('coffee', name: 'Coffee', unit: Unit.drink),
        ]),
        runner: (_) async => InsightsReport(
          findings: <HabitFinding>[
            finding(
              InsightKind.dose,
              1,
              -6,
              sameBedtime: finding(InsightKind.dose, 1, -2),
            ),
            finding(
              InsightKind.lastUse,
              60,
              -12,
              sameBedtime: finding(InsightKind.lastUse, 60, -4),
            ),
          ],
          refused: const <HabitRefusal>[],
        ),
      ),
    );

    expect(
      find.text(
        'On days your last use of Coffee is an hour later, your REM sleep '
        'that night averages 12 min less.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('12 min less per hour later, 4 min of it at the same bedtime'),
      findsOneWidget,
    );
    expect(
      find.text(
        'More per extra drink: REM sleep 6 min less, 2 min of it at the '
        'same bedtime',
      ),
      findsOneWidget,
    );
    expect(find.text(metricEvidence('sleepREM')!), findsOneWidget);
  });

  testWidgets('the two largest cards show, the rest behind More on what it '
      'costs', (WidgetTester tester) async {
    _connected();
    const List<String> metrics = <String>[
      'sleepDeep',
      'restingHeartRate',
      'respiratoryRate',
      'appleSleepingWristTemperature',
      'stepCount',
    ];
    // Two habits x five families: ten cards, each its effect in floors.
    HabitFinding finding(String habit, String metric, double floors) =>
        HabitFinding(
          habitId: habit,
          metricId: metric,
          lagDays: 1,
          usableDays: 120,
          exposedDays: 60,
          raw: null,
          effect: -floors * metricFloor(metric),
          interval: stats.Interval(
            -floors * 1.5 * metricFloor(metric),
            -floors * 0.5 * metricFloor(metric),
          ),
          standardized: -0.5,
          pValue: 0.001,
        );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[
          fakeVice('coffee', name: 'Coffee'),
          fakeVice('tea', name: 'Tea'),
        ]),
        runner: (_) async => InsightsReport(
          findings: <HabitFinding>[
            for (int i = 0; i < metrics.length; i++) ...<HabitFinding>[
              finding('coffee', metrics[i], 20.0 - i),
              finding('tea', metrics[i], 10.0 - i),
            ],
          ],
          refused: const <HabitRefusal>[],
        ),
      ),
    );

    expect(find.text('Coffee · sleep'), findsOneWidget);
    expect(find.text('Coffee · heart'), findsOneWidget);
    expect(find.text('Coffee · breathing'), findsNothing);
    // Coffee's heart card leads with resting heart rate: one line for what
    // 5 bpm has been shown to do.
    expect(find.text(metricEvidence('restingHeartRate')!), findsOneWidget);
    expect(find.text(InsightsPage.more(8)), findsOneWidget);
    await _openCosts(tester);
    // Both activity cards lead with steps.
    expect(find.text(metricEvidence('stepCount')!), findsNWidgets(2));
    for (final String habit in <String>['Coffee', 'Tea']) {
      for (final String family in <String>[
        'sleep',
        'heart',
        'breathing',
        'temperature',
        'activity',
      ]) {
        expect(find.text('$habit · $family'), findsOneWidget);
      }
    }
  });

  testWidgets('two habits used on the same days are refused as entangled', (
    WidgetTester tester,
  ) async {
    _connected();
    final journal = insightsJournal(teaWithCoffee: true);
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(journal.health)),
        activities: AsyncData<List<ViceActivity>>(journal.activities),
      ),
    );

    expect(find.text(InsightsPage.nothingClear), findsOneWidget);
    await _openCosts(tester);
    expect(
      find.text('Used together with Tea, so the two can’t be told apart'),
      findsOneWidget,
    );
    expect(
      find.text('Used together with Coffee, so the two can’t be told apart'),
      findsOneWidget,
    );
  });

  testWidgets('an archived habit gets no card, no row and no copied line', (
    WidgetTester tester,
  ) async {
    _connected();
    final List<String?> copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[
          fakeVice('coffee', name: 'Coffee', archived: true),
          ...insightsVices.where((Vice v) => v.id != 'coffee'),
        ]),
      ),
    );

    expect(find.text(InsightsPage.nothingClear), findsOneWidget);
    expect(find.textContaining('Coffee'), findsNothing);

    await tester.tap(find.text(InsightsPage.copyLabel));
    await tester.pump();
    await _openCosts(tester);
    expect(find.textContaining('Coffee'), findsNothing);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(copied.single, isNot(contains('Coffee')));
    expect(copied.single, contains('Tea: '));
  });

  testWidgets('a habit used on the days of an archived one is still told '
      'apart from it', (WidgetTester tester) async {
    _connected();
    final journal = insightsJournal(teaWithCoffee: true);
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(journal.health)),
        activities: AsyncData<List<ViceActivity>>(journal.activities),
        vices: AsyncData<List<Vice>>(<Vice>[
          fakeVice('coffee', name: 'Coffee', archived: true),
          ...insightsVices.where((Vice v) => v.id != 'coffee'),
        ]),
      ),
    );

    expect(find.text(InsightsPage.nothingClear), findsOneWidget);
    expect(find.textContaining('after Tea'), findsNothing);
    await _openCosts(tester);
    expect(
      find.text('Used together with Coffee, so the two can’t be told apart'),
      findsOneWidget,
    );
    expect(find.text('Coffee'), findsNothing);
  });

  testWidgets('Health is asked for only when Connect is tapped, then read', (
    WidgetTester tester,
  ) async {
    final FakeHealthSource health = FakeHealthSource(
      read: HealthValues(insightsJournal().health),
    );
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text(InsightsPage.connectLabel), findsOneWidget);
    expect(find.text(InsightsPage.costsHeading), findsNothing);
    expect(health.authorizationRequests, 0);
    expect(health.reads, 0);

    await tester.tap(find.text(InsightsPage.connectLabel));
    await tester.pumpAndSettle();

    expect(health.authorizationRequests, 1);
    expect(health.reads, greaterThan(0));
    expect(find.text(InsightsPage.connectLabel), findsNothing);
    expect(find.textContaining('On nights after Coffee'), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(healthConnectedKey), isTrue);
  });

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

  testWidgets('the journal is not read until Health has values', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        onJournalOpened: () => opened++,
      ),
    );
    expect(find.text(InsightsPage.connectLabel), findsOneWidget);
    expect(opened, 0);

    await tester.tap(find.text(InsightsPage.connectLabel));
    await tester.pumpAndSettle();
    expect(opened, greaterThan(0));
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

  testWidgets(
    'on macOS the card says Health is on the iPhone and asks nothing',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final FakeHealthSource health = FakeHealthSource();
      await _pump(tester, insightsOverrides(health: health));

      expect(find.text(InsightsPage.onIPhone), findsOneWidget);
      expect(find.text(InsightsPage.connectLabel), findsNothing);
      expect(health.authorizationRequests, 0);
      expect(health.reads, 0);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('loading shows a message until the journal answers', (
    WidgetTester tester,
  ) async {
    _connected();
    await tester.pumpWidget(
      ProviderScope(
        overrides: insightsOverrides(
          health: FakeHealthSource(
            read: HealthValues(insightsJournal().health),
          ),
          activities: const AsyncLoading<List<ViceActivity>>(),
        ),
        child: const MaterialApp(home: InsightsPage()),
      ),
    );
    await tester.pump();

    expect(find.text(InsightsPage.loadingLabel), findsOneWidget);
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

  testWidgets('an entry of a habit that is gone does not date the span', (
    WidgetTester tester,
  ) async {
    _connected();
    final List<ViceActivity> journal = insightsJournal().activities;
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        activities: AsyncData<List<ViceActivity>>(<ViceActivity>[
          ...journal,
          fakeActivity('gone', 1, DateTime(2001, 5, 6)),
        ]),
      ),
    );

    final DateTime first = insightsFirstDay(
      insightsFirstDays(journal),
      (_) => true,
    )!;
    expect(find.text(InsightsPage.span(first)), findsOneWidget);
    expect(find.text(InsightsPage.span(DateTime(2001, 5, 6))), findsNothing);
  });

  testWidgets('the page says where the journal starts, and copies its '
      'findings and refusals as text', (WidgetTester tester) async {
    _connected();
    final List<String?> copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
      ),
    );

    final DateTime first = insightsFirstDay(
      insightsFirstDays(insightsJournal().activities),
      (_) => true,
    )!;
    expect(find.text(InsightsPage.span(first)), findsOneWidget);

    await tester.tap(find.text(InsightsPage.copyLabel));
    await tester.pump();

    expect(find.text(InsightsPage.copied), findsOneWidget);
    expect(copied, hasLength(1));
    final String text = copied.single!;
    final List<String> lines = text.split('\n');
    expect(lines.take(4), <String>[
      InsightsPage.title,
      InsightsPage.span(first),
      '',
      InsightsPage.costsHeading,
    ]);
    expect(lines, contains('Coffee · sleep'));
    expect(
      lines,
      contains(
        matches(
          RegExp(
            r'^On nights after Coffee, your deep sleep averages 1\d min '
            r'less\.$',
          ),
        ),
      ),
    );
    expect(lines, contains(matches(RegExp(r'^Range: \d+ to \d+ min less$'))));
    expect(
      lines,
      contains(matches(RegExp(r'^From \d+ days, \d+ of them with Coffee$'))),
    );
    final int refused = lines.indexOf(InsightsPage.refusedHeading);
    expect(refused, greaterThan(lines.indexOf('Coffee · sleep')));
    expect(lines.sublist(refused + 1, refused + 3), <Object>[
      'Tea: Within the noise: no clear difference',
      matches(RegExp(r'^Water: Too few days yet: \d+ of \d+$')),
    ]);
    expect(text.trimRight().endsWith(InsightsPage.foot), isTrue);
  });

  test('copied text with nothing found and an empty journal says so', () {
    expect(
      insightsText(
        cards: const <InsightCard>[],
        refused: const <HabitRefusal>[],
        firstDay: null,
        nameOf: (String id) => id,
        locale: 'en',
      ),
      '${InsightsPage.title}\n\n'
      '${InsightsPage.costsHeading}\n'
      '${InsightsPage.nothingClear}: ${InsightsPage.nothingClearBody}\n\n'
      '${InsightsPage.foot}\n',
    );
  });

  test('copied text gives the bedtime line under its sentence', () {
    final HabitFinding time = HabitFinding(
      habitId: 'coffee',
      metricId: 'sleepAsleep',
      lagDays: 1,
      usableDays: 120,
      exposedDays: 120,
      raw: null,
      kind: InsightKind.lastUse,
      step: 60,
      effect: -11,
      interval: stats.Interval(-15, -7),
      standardized: -0.5,
      pValue: 0.001,
      sameBedtime: HabitRefusal(
        habitId: 'coffee',
        metricId: 'sleepAsleep',
        lagDays: 1,
        usableDays: 110,
        exposedDays: 110,
        raw: null,
        kind: InsightKind.lastUse,
        step: 60,
        reason: RefusalReason.withinNoise,
        effect: -1,
      ),
    );
    final List<String> lines = insightsText(
      cards: <InsightCard>[
        InsightCard(family: MetricFamily.sleep, headline: time),
      ],
      refused: const <HabitRefusal>[],
      firstDay: null,
      nameOf: (String _) => 'Coffee',
      locale: 'en',
    ).split('\n');
    final int sentence = lines.indexOf(
      'On days your last use of Coffee is an hour later, your time asleep '
      'that night averages 11 min less.',
    );
    expect(sentence, greaterThan(0));
    expect(
      lines[sentence + 1],
      '11 min less per hour later, none of it clear at the same bedtime',
    );
  });

  test('the route opens Insights', () {
    expect(routePage(InsightsPage.route), isA<InsightsPage>());
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

  testWidgets('the page is three question sections, in order, the two '
      'without answers yet saying what will be there', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
      ),
    );

    final List<double> tops = <double>[
      for (final String heading in <String>[
        InsightsPage.costsHeading,
        InsightsPage.cuttingDownHeading,
        InsightsPage.setsOffHeading,
        InsightsPage.copyLabel,
      ])
        tester.getTopLeft(find.text(heading)).dy,
    ];
    expect(tops, orderedEquals(tops.toList()..sort()));
    expect(find.text(InsightsPage.cuttingDownBody), findsOneWidget);
    expect(find.text(InsightsPage.setsOffBody), findsOneWidget);
    expect(find.text(InsightsPage.lastNightHeading), findsNothing);
  });

  testWidgets('with every habit short of days, What it costs says how far '
      'along the furthest is', (WidgetTester tester) async {
    _connected();
    HabitRefusal short(String habit, int days) => HabitRefusal(
      habitId: habit,
      metricId: 'sleepDeep',
      lagDays: 1,
      usableDays: days,
      exposedDays: days ~/ 2,
      raw: null,
      reason: RefusalReason.tooFewDays,
    );
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        runner: (_) async => InsightsReport(
          findings: const <HabitFinding>[],
          refused: <HabitRefusal>[short('coffee', 9), short('tea', 4)],
        ),
      ),
    );

    expect(find.text(InsightsPage.earlyTitle), findsOneWidget);
    expect(find.text(InsightsPage.earlyBody(9, 21)), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(9 / 21, 1e-9),
    );
    expect(find.text(InsightsPage.nothingClear), findsNothing);
  });

  testWidgets('last night against the usual leads the page, with what was '
      'logged the day before', (WidgetTester tester) async {
    _connected();
    final DateTime yesterday = insightsToday.subtract(const Duration(days: 1));
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        vices: AsyncData<List<Vice>>(<Vice>[
          ...insightsVices,
          fakeVice('wine', name: 'Wine', unit: Unit.drink),
        ]),
        activities: AsyncData<List<ViceActivity>>(<ViceActivity>[
          ...insightsJournal().activities.where(
            (ViceActivity a) => a.viceID != 'water',
          ),
          fakeActivity('wine', 2, yesterday.add(const Duration(hours: 20))),
          // After midnight: still the evening before.
          fakeActivity('wine', 1, insightsToday.add(const Duration(hours: 1))),
          // The day before yesterday, so not counted.
          fakeActivity('wine', 4, yesterday.subtract(const Duration(hours: 2))),
        ]),
        lastNight: const LastNight(
          sleepingHeartRate: NightCompare(
            value: 57.2,
            usual: 54,
            low: 53,
            high: 55,
          ),
          heartRateVariability: NightCompare(
            value: 41,
            usual: 48,
            low: 45,
            high: 51,
          ),
          asleep: NightCompare(value: 410, usual: 435, low: 420, high: 450),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text(InsightsPage.lastNightHeading)).dy,
      lessThan(tester.getTopLeft(find.text(InsightsPage.costsHeading)).dy),
    );
    expect(find.text('Sleeping heart rate'), findsOneWidget);
    expect(find.text('57 bpm', findRichText: true), findsOneWidget);
    expect(find.text('usual 54 · 3 above'), findsOneWidget);
    expect(find.text('usual range 45–51 · below'), findsOneWidget);
    expect(find.text('6 h 50 m', findRichText: true), findsOneWidget);
    expect(find.text('usual 7 h 15 m · 25 min under'), findsOneWidget);
    expect(
      find.textContaining('Yesterday: Wine 3 drinks, last at 1:00'),
      findsOneWidget,
    );
  });

  testWidgets('a night in the usual range says so', (
    WidgetTester tester,
  ) async {
    _connected();
    await _pump(
      tester,
      insightsOverrides(
        health: FakeHealthSource(read: HealthValues(insightsJournal().health)),
        activities: const AsyncData<List<ViceActivity>>(<ViceActivity>[]),
        lastNight: const LastNight(
          sleepingHeartRate: NightCompare(
            value: 54.4,
            usual: 54,
            low: 53,
            high: 55,
          ),
        ),
      ),
    );

    expect(find.text('usual 54 · in your usual range'), findsOneWidget);
    expect(find.text('HRV'), findsNothing);
    expect(find.text('Nothing logged yesterday'), findsOneWidget);
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

    test('the check as text, one row a line', () {
      const LastNight night = LastNight(
        sleepingHeartRate: NightCompare(
          value: 57,
          usual: 54,
          low: 53,
          high: 55,
        ),
        heartRateVariability: NightCompare(
          value: 41,
          usual: 48,
          low: 45,
          high: 51,
        ),
        asleep: NightCompare(value: 410, usual: 435, low: 420, high: 450),
      );
      final List<String> lines = lastNightText(night, const <YesterdayLine>[
        (mark: null, text: 'Yesterday: Wine 3 drinks, last at 22:05'),
      ]);
      expect(lines, <String>[
        'Sleeping heart rate: 57 bpm, usual 54 · 3 above',
        'HRV: 41 ms, usual range 45–51 · below',
        'Sleep: 6 h 50 m, usual 7 h 15 m · 25 min under',
        'Yesterday: Wine 3 drinks, last at 22:05',
      ]);
      expect(lastNightText(night, null), hasLength(3));
      expect(
        insightsText(
          cards: const <InsightCard>[],
          refused: const <HabitRefusal>[],
          firstDay: null,
          nameOf: (String id) => id,
          locale: 'en',
          lastNight: lines,
          emptyTitle: InsightsPage.earlyTitle,
          emptyBody: InsightsPage.earlyBody(9, 21),
        ),
        '${InsightsPage.title}\n\n'
        '${InsightsPage.lastNightHeading}\n${lines.join('\n')}\n\n'
        '${InsightsPage.costsHeading}\n'
        '${InsightsPage.earlyTitle}: ${InsightsPage.earlyBody(9, 21)}\n\n'
        '${InsightsPage.foot}\n',
      );
    });
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

    test('a finding names the habit, the outcome, the size and the range', () {
      final HabitFinding f = finding(
        HealthMetric.sleepDeep.id,
        -18.2,
        const stats.Interval(-29.4, -7.1),
      );
      expect(
        findingSentence(f, 'Coffee', 'en'),
        'On nights after Coffee, your deep sleep averages 18 min less.',
      );
      expect(findingRange(f, 'en'), 'Range: 7 to 29 min less');
      expect(findingBasis(f, 'Coffee'), 'From 64 days');
    });

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
