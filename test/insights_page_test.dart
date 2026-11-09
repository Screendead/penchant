import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/insights_provider.dart';

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

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text(InsightsPage.foundHeading), findsOneWidget);
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

    expect(find.text(InsightsPage.refusedHeading), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Within the noise: no clear difference'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('Too few days yet'), findsOneWidget);
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
    expect(find.text('Tea'), findsOneWidget);
    expect(
      find.text('Could be chance: one of many comparisons'),
      findsOneWidget,
    );
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
    expect(
      find.text('Used together with Tea, so the two can’t be told apart'),
      findsOneWidget,
    );
    expect(
      find.text('Used together with Coffee, so the two can’t be told apart'),
      findsOneWidget,
    );
  });

  testWidgets('Health is asked for only when Connect is tapped, then read', (
    WidgetTester tester,
  ) async {
    final FakeHealthSource health = FakeHealthSource(
      read: HealthValues(insightsJournal().health),
    );
    await _pump(tester, insightsOverrides(health: health));

    expect(find.text(InsightsPage.connectLabel), findsOneWidget);
    expect(find.text(InsightsPage.foundHeading), findsNothing);
    expect(health.authorizationRequests, 0);
    expect(health.reads, 0);

    await tester.tap(find.text(InsightsPage.connectLabel));
    await tester.pumpAndSettle();

    expect(health.authorizationRequests, 1);
    expect(health.reads, greaterThan(0));
    expect(find.text('Connected'), findsOneWidget);
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
      InsightsPage.foundHeading,
    ]);
    expect(lines, contains('Coffee · deep sleep'));
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
    expect(refused, greaterThan(lines.indexOf('Coffee · deep sleep')));
    expect(lines.sublist(refused + 1, refused + 3), <Object>[
      'Tea: Within the noise: no clear difference',
      matches(RegExp(r'^Water: Too few days yet: \d+ of \d+$')),
    ]);
    expect(text.trimRight().endsWith(InsightsPage.foot), isTrue);
  });

  test('copied text with nothing found and an empty journal says so', () {
    expect(
      insightsText(
        findings: const <HabitFinding>[],
        refused: const <HabitRefusal>[],
        firstDay: null,
        nameOf: (String id) => id,
        locale: 'en',
      ),
      '${InsightsPage.title}\n\n'
      '${InsightsPage.foundHeading}\n'
      '${InsightsPage.nothingClear}: ${InsightsPage.nothingClearBody}\n\n'
      '${InsightsPage.foot}\n',
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
