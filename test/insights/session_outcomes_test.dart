import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import '../fakes.dart';

final DateTime start = DateTime(2026, 1, 5);

DailyOutcome outcome(int day, String metric, double value) =>
    DailyOutcome(date: addDays(start, day), metricId: metric, value: value);

Map<DateTime, double> series(List<DailyOutcome> outcomes, String metric) =>
    <DateTime, double>{
      for (final DailyOutcome o in outcomes)
        if (o.metricId == metric) o.date: o.value,
    };

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// One habit on a fair coin's days, and [metric]'s sessions on about 60% of
// days, of 40 min give or take 8, none on the day after the habit when
// [skipsAfter]. Sessions only: days without one are absent, as Health gives
// them.
InsightsInput sessionInput(int seed, String metric, {bool skipsAfter = true}) {
  final Random random = Random(seed);
  const int days = 150;
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final bool used = random.nextBool();
    if (used) {
      uses.add(
        HabitUse(
          habitId: 'habit1',
          at: day.add(const Duration(hours: 20)),
          amount: 1,
        ),
      );
    }
    final bool session = random.nextDouble() < 0.6;
    if (session && !(used && skipsAfter)) {
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: metric,
          value: 40 + 8 * gaussian(random),
        ),
      );
    }
  }
  final DateTime through = addDays(start, days);
  return InsightsInput(
    uses: uses,
    outcomes: withSessionZeros(outcomes, through: through),
    from: start,
    through: through,
  );
}

void main() {
  group('withSessionZeros', () {
    final List<DailyOutcome> sessions = <DailyOutcome>[
      for (int i = 0; i < minSessionDays; i++)
        outcome(3 + 2 * i, 'workoutMinutes', 30),
    ];

    test('fills the days without a session from the first one through the '
        'last day, keeping every value', () {
      final DateTime through = addDays(start, 40);
      final Map<DateTime, double> got = series(
        withSessionZeros(sessions, through: through),
        'workoutMinutes',
      );
      expect(
        got.keys.reduce((a, b) => a.isBefore(b) ? a : b),
        addDays(start, 3),
      );
      expect(got.length, 38);
      expect(got[addDays(start, 4)], 0);
      expect(got[addDays(start, 5)], 30);
      expect(got[through], 0);
      expect(got.containsKey(addDays(start, 2)), isFalse);
      expect(got.containsKey(addDays(through, 1)), isFalse);
    });

    test('crosses a DST change by local midnights', () {
      final List<DailyOutcome> autumn = <DailyOutcome>[
        for (int i = 0; i < minSessionDays; i++)
          DailyOutcome(
            date: addDays(DateTime(2026, 10, 20), i * 2),
            metricId: 'mindfulMinutes',
            value: 10,
          ),
      ];
      final Map<DateTime, double> got = series(
        withSessionZeros(autumn, through: DateTime(2026, 11, 20)),
        'mindfulMinutes',
      );
      expect(got.keys.every((d) => d == startOfDay(d)), isTrue);
      expect(got.length, 32);
    });

    test('leaves out a session metric with too few days of sessions', () {
      final List<DailyOutcome> few = <DailyOutcome>[
        ...sessions.sublist(1),
        outcome(5, 'stepCount', 4000),
      ];
      final List<DailyOutcome> got = withSessionZeros(
        few,
        through: addDays(start, 40),
      );
      expect(got.where((o) => o.metricId == 'workoutMinutes'), isEmpty);
      expect(got.where((o) => o.metricId == 'stepCount'), hasLength(1));
    });

    test('never fills a measure that is not counted in sessions', () {
      final List<DailyOutcome> steps = <DailyOutcome>[
        outcome(1, 'stepCount', 4000),
        outcome(9, 'stepCount', 5000),
      ];
      expect(withSessionZeros(steps, through: addDays(start, 40)), steps);
    });

    test('a person with no sessions has none', () {
      expect(withSessionZeros(const [], through: addDays(start, 40)), isEmpty);
    });
  });

  test('InsightsInput.from fills through yesterday, never today', () {
    final DateTime today = DateTime(2026, 6, 1);
    final InsightsInput input = InsightsInput.from(
      activities: [fakeActivity('habit1', 1, DateTime(2026, 5, 1, 9))],
      health: <hs.DailyOutcome>[
        for (int i = 0; i < minSessionDays; i++)
          hs.DailyOutcome(
            addDays(DateTime(2026, 5, 1), i * 2),
            'workoutMinutes',
            30,
          ),
        hs.DailyOutcome(today, 'workoutMinutes', 20),
      ],
      today: today,
    );
    final Map<DateTime, double> got = series(input.outcomes, 'workoutMinutes');
    expect(got.containsKey(today), isFalse);
    expect(got[DateTime(2026, 5, 31)], 0);
    expect(got.length, 31);
  });

  test('the new outcomes carry a floor, a family, copy and a source line', () {
    for (final String id in hs.sessionMetricIds) {
      expect(hs.HealthMetric.values.map((m) => m.id), contains(id));
      expect(metricFloors[id], isNotNull, reason: id);
      expect(metricCopy(id), isNotNull, reason: id);
      expect(metricEvidence(id), isNotNull, reason: id);
    }
    expect(metricFloors['workoutMinutes']!.family, MetricFamily.activity);
    expect(metricFloors['mindfulMinutes']!.family, MetricFamily.mindfulness);
  });

  for (final (String metric, MetricFamily family) in <(String, MetricFamily)>[
    ('workoutMinutes', MetricFamily.activity),
    ('mindfulMinutes', MetricFamily.mindfulness),
  ]) {
    test('a habit followed by skipped $metric is found, on its '
        '${family.label} card', () {
      int found = 0;
      for (int seed = 0; seed < 20; seed++) {
        final InsightsReport report = computeInsights(
          sessionInput(seed, metric),
        );
        expect(report.floors[metric], greaterThanOrEqualTo(13));
        final HabitFinding? use = report.findings
            .where((f) => f.metricId == metric && f.kind == InsightKind.use)
            .firstOrNull;
        if (use == null) continue;
        found++;
        // About 24 min a day against none: 60% of 40 min.
        expect(use.effect, inInclusiveRange(-32, -16));
        final InsightCard card = insightCards(
          report.findings,
          floors: report.floors,
        ).firstWhere((c) => c.headline.metricId == metric);
        expect(card.family, family);
        expect(
          findingSentence(use, 'Wine', 'en'),
          startsWith('On days after Wine, your '),
        );
      }
      expect(found, greaterThanOrEqualTo(18));
    });

    test('on noise, $metric rarely yields a finding', () {
      int found = 0;
      for (int seed = 0; seed < 40; seed++) {
        final InsightsReport report = computeInsights(
          sessionInput(seed, metric, skipsAfter: false),
        );
        if (report.findings.any((f) => f.metricId == metric)) found++;
      }
      expect(found, lessThanOrEqualTo(2));
    });
  }
}
