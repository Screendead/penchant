import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart'
    show HealthSample, HealthSampleMetric;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

import 'before_use_synthetic.dart';
import 'hours_after_synthetic.dart';

BeforeUse one(List<BeforeUse> all, BeforeUseKind kind, String metricId) =>
    all.singleWhere((b) => b.kind == kind && b.metricId == metricId);

BeforeUse fitted(double p, {double effect = 30}) => BeforeUse(
  habitId: 'Coffee',
  metricId: 'sleepAsleep',
  kind: BeforeUseKind.whether,
  usableDays: 60,
  exposedDays: 30,
  effect: effect,
  interval: Interval(effect - 5, effect + 5),
  pValue: p,
);

void main() {
  test('a first use is the earliest from 05:00, and one after midnight '
      'belongs to the evening before', () {
    final DateTime day = DateTime(2026, 6, 10);
    final Map<DateTime, int> first = firstUseMinutes(<HabitUse>[
      HabitUse(habitId: 'a', at: day.add(const Duration(hours: 1)), amount: 1),
      HabitUse(habitId: 'a', at: day.add(const Duration(hours: 9)), amount: 1),
      HabitUse(habitId: 'a', at: day.add(const Duration(hours: 8)), amount: 0),
      HabitUse(habitId: 'a', at: day.add(const Duration(hours: 14)), amount: 2),
    ])['a']!;
    expect(first[day], 9 * 60);
    expect(first[addDays(day, -1)], 25 * 60);
  });

  test('short nights that bring on use, more of it and earlier are found, '
      'each in minutes of sleep', () {
    final BeforeDays d = beforeDays(3, days: 240, reverse: 1);
    final List<BeforeUse> all = beforeUse(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      through: d.through,
    );
    expect(all, hasLength(9));
    for (final BeforeUseKind kind in <BeforeUseKind>[
      BeforeUseKind.whether,
      BeforeUseKind.amount,
      BeforeUseKind.firstUse,
    ]) {
      final BeforeUse b = one(all, kind, 'sleepAsleep');
      expect(b.found, isTrue, reason: '$kind ${b.refusal}');
      expect(b.effect, lessThan(0), reason: '$kind');
      expect(b.interval!.high, lessThan(0), reason: '$kind');
    }
    expect(one(all, BeforeUseKind.firstUse, 'sleepAsleep').step, 60);
    expect(one(all, BeforeUseKind.amount, 'sleepAsleep').spread, isNotNull);
  });

  test('too few days, a steady amount and a set time are refused unfitted', () {
    final BeforeDays few = beforeDays(1, days: 15);
    for (final BeforeUse b in beforeUse(
      uses: few.uses,
      outcomes: OutcomeSeries.fromOutcomes(few.outcomes),
      through: few.through,
    )) {
      expect(b.refusal, RefusalReason.tooFewDays);
      expect(b.pValue, isNull);
    }
    final BeforeDays d = beforeDays(2);
    final Set<DateTime> days = <DateTime>{
      for (final HabitUse u in d.uses) startOfDay(u.at),
    };
    final List<BeforeUse> steady = beforeUse(
      uses: <HabitUse>[
        for (final DateTime day in days)
          HabitUse(
            habitId: 'Coffee',
            at: day.add(const Duration(hours: 8)),
            amount: 2,
          ),
      ],
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      through: d.through,
    );
    expect(
      one(steady, BeforeUseKind.amount, 'sleepAsleep').refusal,
      RefusalReason.steadyAmount,
    );
    expect(
      one(steady, BeforeUseKind.firstUse, 'sleepAsleep').refusal,
      RefusalReason.steadyTiming,
    );
    expect(one(steady, BeforeUseKind.whether, 'sleepAsleep').pValue, isNotNull);
  });

  test('days after through, a skipped habit and a measure Health lacks are '
      'left out', () {
    final BeforeDays d = beforeDays(4);
    final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(<DailyOutcome>[
      for (final DailyOutcome o in d.outcomes)
        if (o.metricId != 'restingHeartRate') o,
    ]);
    final List<BeforeUse> all = beforeUse(
      uses: d.uses,
      outcomes: outcomes,
      through: addDays(d.through, -30),
    );
    expect(all.map((b) => b.metricId).toSet(), <String>{
      'sleepAsleep',
      'heartRateVariabilitySDNN',
    });
    expect(
      one(all, BeforeUseKind.whether, 'sleepAsleep').usableDays,
      lessThanOrEqualTo(90),
    );
    expect(
      beforeUse(
        uses: d.uses,
        outcomes: outcomes,
        through: d.through,
        skip: <String>{'Coffee'},
      ),
      isEmpty,
    );
  });

  test('the family decides: a finding beside many null comparisons is '
      'chance, one under its floor too small', () {
    final List<BeforeUse> judged = judgeBeforeUse(
      <BeforeUse>[fitted(0.04), fitted(0.0001), fitted(0.0001, effect: 6)],
      alongside: List<double>.filled(40, 0.6),
      sizeOf: (b) => practicalSize(b.asFinding),
    );
    expect(judged[0].refusal, RefusalReason.chance);
    expect(judged[1].found, isTrue);
    expect(judged[2].refusal, RefusalReason.tooSmall);
    expect(
      judgeBeforeUse(
        <BeforeUse>[fitted(0.04)],
        alongside: const <double>[],
        sizeOf: (b) => 2,
      ).single.found,
      isTrue,
    );
  });

  test('the report judges before-use in the page family, without archived '
      'habits or today', () {
    final BeforeDays d = beforeDays(3, days: 240, reverse: 1);
    InsightsReport report({Set<String> archived = const <String>{}}) =>
        computeInsights(
          InsightsInput(
            uses: d.uses,
            outcomes: d.outcomes,
            from: syntheticStart,
            through: addDays(d.through, 1),
            archived: archived,
          ),
        );
    final BeforeUse found = one(
      report().beforeUse,
      BeforeUseKind.whether,
      'sleepAsleep',
    );
    expect(found.found, isTrue);
    expect(report(archived: <String>{'Coffee'}).beforeUse, isEmpty);
  });

  test('the hour before: nothing without heart rate, and too few uses says '
      'so', () {
    final Synthetic s = synthetic(1, days: 12);
    final HoursAfterPlan plan = planHoursAfter(
      s.uses,
      s.through,
      bed: s.samples[HealthSampleMetric.bed.id]!,
    );
    expect(
      hourBefore(
        plan: plan,
        uses: s.uses,
        samples: <String, List<HealthSample>>{
          HealthSampleMetric.bed.id: s.samples[HealthSampleMetric.bed.id]!,
        },
      ),
      isEmpty,
    );
    final BeforeUse b = hourBefore(
      plan: plan,
      uses: s.uses,
      samples: s.samples,
    ).single;
    expect(b.kind, BeforeUseKind.hourBefore);
    expect(b.refusal, RefusalReason.tooFewDays);
    expect(b.pValue, isNull);
    expect(
      hourBefore(
        plan: plan,
        uses: s.uses,
        samples: s.samples,
        skip: <String>{'Coffee'},
      ),
      isEmpty,
    );
  });
}
