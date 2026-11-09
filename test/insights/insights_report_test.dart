import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
const int days = 120;

final List<String> habitIds = <String>[for (int i = 1; i <= 5; i++) 'habit$i'];

final List<String> metricIds = <String>[
  for (final HealthMetric m in <HealthMetric>[
    HealthMetric.sleepAsleep,
    HealthMetric.sleepCore,
    HealthMetric.sleepDeep,
    HealthMetric.sleepREM,
    HealthMetric.heartRateVariabilitySDNN,
    HealthMetric.restingHeartRate,
    HealthMetric.respiratoryRate,
    HealthMetric.stepCount,
    HealthMetric.activeEnergyBurned,
  ])
    m.id,
];

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// Five habits each used on a fair coin's days, and nine outcomes of
// independent noise (sd 20), the next day's value of the first [effectOn]
// moved by [effect] after a day with the first habit.
InsightsInput noiseInput(int seed, {double effect = 0}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final Set<String> used = <String>{
      for (final String id in habitIds)
        if (random.nextBool()) id,
    };
    for (final String id in used) {
      uses.add(
        HabitUse(habitId: id, at: day.add(const Duration(hours: 9)), amount: 1),
      );
    }
    for (final String metric in metricIds) {
      final bool moved = metric == metricIds.first && used.contains('habit1');
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: metric,
          value: 100 + (moved ? effect : 0) + 20 * gaussian(random),
        ),
      );
    }
  }
  return InsightsInput(
    uses: uses,
    outcomes: outcomes,
    from: start,
    through: addDays(start, days),
  );
}

List<HabitInsight> everyComparison(InsightsInput input) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  return <HabitInsight>[
    for (final String metric in metricIds)
      ...whatFollows(
        habits: habits,
        outcomes: outcomes,
        metricId: metric,
        lagDays: insightsLagDays,
        from: input.from,
        through: input.through,
      ),
  ];
}

Set<(String, String)> pairs(Iterable<HabitFinding> findings) =>
    <(String, String)>{for (final f in findings) (f.habitId, f.metricId)};

void main() {
  test('on pure noise, false findings across 5 habits x 9 outcomes fall from '
      'about 1 in 20 checks to about 1 in 500', () {
    const int seeds = 400;
    int checks = 0, rawFindings = 0, rawReports = 0;
    int findings = 0, reports = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final InsightsInput input = noiseInput(seed);
      final List<HabitInsight> raw = everyComparison(input);
      checks += raw.length;
      final int rawFound = raw.whereType<HabitFinding>().length;
      rawFindings += rawFound;
      if (rawFound > 0) rawReports++;

      final Set<(String, String)> corrected = pairs(
        controlFalseDiscoveries(raw).whereType<HabitFinding>(),
      );
      final int found = corrected.length;
      if (seed < 20 || found > 0) {
        expect(pairs(computeInsights(input).findings), corrected);
      }
      findings += found;
      if (found > 0) reports++;
    }

    // ignore: avoid_print
    print(
      'MEASURE checks=$checks raw=$rawFindings rawReports=$rawReports after=$findings reports=$reports',
    );
    expect(checks, seeds * 45);
    // Before: each check alone at 95%, so most reports show one or more.
    expect(rawFindings / checks, inInclusiveRange(0.03, 0.07));
    expect(rawReports / seeds, greaterThan(0.75));
    // After: q = 0.1 bounds the chance a pure-noise report shows anything at
    // all at about 10%.
    expect(findings / checks, lessThan(0.005));
    expect(reports / seeds, lessThan(0.15));
  });

  test('a real effect among 45 comparisons is still found', () {
    for (int seed = 0; seed < 50; seed++) {
      final InsightsReport report = computeInsights(
        noiseInput(seed, effect: -30),
      );
      final HabitFinding found = report.findings.firstWhere(
        (f) => f.habitId == 'habit1' && f.metricId == metricIds.first,
      );
      expect(found.effect, inInclusiveRange(-45, -15));
      expect(found.interval.high, lessThan(0));
    }
  });

  test('a finding that does not survive the correction is refused as chance, '
      'and that reason outranks the noise', () {
    const int seeds = 200;
    for (int seed = 0; seed < seeds; seed++) {
      final InsightsInput input = noiseInput(seed);
      final List<HabitInsight> corrected = controlFalseDiscoveries(
        everyComparison(input),
      );
      final HabitRefusal? chance = corrected
          .whereType<HabitRefusal>()
          .where((r) => r.reason == RefusalReason.chance)
          .firstOrNull;
      if (chance == null) continue;
      final List<HabitInsight> sameHabit = <HabitInsight>[
        for (final HabitInsight r in corrected)
          if (r.habitId == chance.habitId) r,
      ];
      if (sameHabit.any((r) => r is HabitFinding)) continue;

      expect(chance.interval!.crossesZero, isFalse);
      expect(chance.pValue, lessThan(0.05));
      expect(
        sameHabit.whereType<HabitRefusal>().map((r) => r.reason),
        contains(RefusalReason.withinNoise),
      );
      expect(
        computeInsights(
          input,
        ).refused.singleWhere((r) => r.habitId == chance.habitId).reason,
        RefusalReason.chance,
      );
      return;
    }
    fail('no chance refusal without a sibling finding in $seeds seeds');
  });

  group('a refusal for too few days says which side is short', () {
    HabitRefusal tooFew(int usable, int exposed) => HabitRefusal(
      habitId: 'Coffee',
      metricId: metricIds.first,
      lagDays: 1,
      usableDays: usable,
      exposedDays: exposed,
      raw: null,
      reason: RefusalReason.tooFewDays,
    );
    String reason(HabitRefusal r) => refusalReason(r, (id) => id);

    test('too few days in all', () {
      expect(reason(tooFew(12, 6)), 'Too few days yet: 12 of 21');
    });

    test('too few days with it', () {
      expect(reason(tooFew(60, 4)), 'Too few days with it yet: 4 of 7');
    });

    test('an unbroken streak, where waiting will not help', () {
      expect(
        reason(tooFew(60, 57)),
        'Used almost every day: too few days without it to compare',
      );
    });
  });

  test('a habit logged unevenly over time says so', () {
    expect(
      refusalReason(
        const HabitRefusal(
          habitId: 'Tea',
          metricId: 'sleepDeep',
          lagDays: 1,
          usableDays: 121,
          exposedDays: 23,
          raw: null,
          reason: RefusalReason.uneven,
        ),
        (id) => id,
      ),
      'Logged unevenly over time, so it can’t be told apart from other changes',
    );
  });
}
