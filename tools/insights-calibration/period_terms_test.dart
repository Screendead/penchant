// Monte Carlo rates for the period terms and the mixed-months guard in
// lib/insights/what_follows.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/period_terms_test.dart
// Each line prints the outcome counts of one scenario: findings, and each
// refusal reason.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/what_follows.dart';

const String metric = 'outcome';
final DateTime january5 = DateTime(2026, 1, 5);

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

HabitInsight judge(
  Set<int> useDays,
  double Function(int day, bool used) value,
  int lastDay,
  Random random,
  DateTime start,
) {
  final List<HabitUse> uses = <HabitUse>[
    for (final int d in useDays)
      HabitUse(
        habitId: 'Coffee',
        at: addDays(start, d).add(const Duration(hours: 9)),
        amount: 1,
      ),
  ];
  final List<DailyOutcome> outcomes = <DailyOutcome>[
    for (int i = 0; i <= lastDay; i++)
      DailyOutcome(
        date: addDays(start, i + 1),
        metricId: metric,
        value: value(i, useDays.contains(i)) + gaussian(random),
      ),
  ];
  return whatFollows(
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
    metricId: metric,
  ).single;
}

void scenario(
  String name,
  int seeds,
  Set<int>? Function(Random random) useDays,
  double Function(int day, bool used) value, {
  DateTime? start,
}) {
  final Map<String, int> counts = <String, int>{};
  int n = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final Random random = Random(seed);
    final Set<int>? days = useDays(random);
    if (days == null) continue;
    n++;
    final HabitInsight r = judge(
      days,
      value,
      days.reduce(max),
      random,
      start ?? january5,
    );
    final String key = switch (r) {
      HabitFinding() => 'finding',
      HabitRefusal(:final RefusalReason reason) => reason.name,
    };
    counts[key] = (counts[key] ?? 0) + 1;
  }
  stdout.writeln('$name (n=$n): $counts');
}

Set<int> bernoulli(Random random, int last, double Function(int day) rate) =>
    <int>{
      0,
      last,
      for (int i = 1; i < last; i++)
        if (random.nextDouble() < rate(i)) i,
    };

/// Runs of [length] days, each day starting one with chance [p].
Set<int> episodes(Random random, int days, double p, int length) => <int>{
  for (int i = 0; i < days; i++)
    if (random.nextDouble() < p) ...<int>[
      for (int k = 0; k < length; k++) i + k,
    ],
};

void main() {
  double none(int day, bool used) => 0;
  double effect(int day, bool used) => used ? -1 : 0;

  test('false findings: use rate changes, outcome steps inside a month', () {
    scenario(
      'fading: 20 of first 30 days, then days 60, 90, 120; step 10 at '
      'day 40',
      100,
      (_) => <int>{
        for (int i = 0; i < 30; i++)
          if (i % 3 != 2) i,
        60,
        90,
        120,
      },
      (i, _) => i <= 40 ? 10 : 0,
    );
    scenario(
      'mirror: skipped on 20 of first 30 days and days 60, 90, 120; '
      'step 10 at day 40',
      100,
      (_) => <int>{
        0,
        121,
        for (int i = 1; i <= 121; i++)
          if (!((i < 30 && i % 3 != 2) || i == 60 || i == 90 || i == 120)) i,
      },
      (i, _) => i <= 40 ? 10 : 0,
    );
    for (final double step in <double>[2, 10]) {
      scenario(
        'mirror: 70% then 97% from day 40; step $step at day 40',
        200,
        (r) => bernoulli(r, 120, (i) => i < 40 ? 0.7 : 0.97),
        (i, _) => i <= 40 ? step : 0,
      );
      scenario(
        'forward: 30% then 3% from day 40; step $step at day 40',
        200,
        (r) => bernoulli(r, 120, (i) => i < 40 ? 0.3 : 0.03),
        (i, _) => i <= 40 ? step : 0,
      );
    }
    for (final int at in <int>[40, 80]) {
      scenario(
        '60% then 30%; step 2 at day $at',
        200,
        (r) => bernoulli(r, 119, (i) => i < 60 ? 0.6 : 0.3),
        (i, _) => i < at ? 0 : -2,
      );
    }
  });

  // Spans of one period (a month plus fewer than 10 usable days), which have
  // no period levels and fall back to the halves guard and level.
  test('false findings in a span of one period', () {
    final DateTime january1 = DateTime(2026, 1, 1);
    scenario(
      'one period, Jan 1 + 38 days: 12 of first 15 days, then days 25, 38; '
      'step 10 at day 15',
      100,
      (_) => <int>{
        for (int i = 0; i < 15; i++)
          if (i % 5 != 4) i,
        25,
        38,
      },
      (i, _) => i < 15 ? 10 : 0,
      start: january1,
    );
    for (final double step in <double>[2, 10]) {
      scenario(
        'one period, Jan 1 + 38 days: 80% then 10% from day 15; step $step '
        'at day 15',
        200,
        (r) => bernoulli(r, 38, (i) => i < 15 ? 0.8 : 0.1),
        (i, _) => i < 15 ? step : 0,
        start: january1,
      );
      scenario(
        'one period, Jan 1 + 38 days: 30% then 90% from day 15; step $step '
        'at day 15',
        200,
        (r) => bernoulli(r, 38, (i) => i < 15 ? 0.3 : 0.9),
        (i, _) => i < 15 ? step : 0,
        start: january1,
      );
      scenario(
        'one period, Jan 5 + 29 days: 80% then 10% from day 12; step $step '
        'at day 12',
        200,
        (r) => bernoulli(r, 29, (i) => i < 12 ? 0.8 : 0.1),
        (i, _) => i < 12 ? step : 0,
      );
    }
  });

  test('cut-downs with a real effect of -1 sd on days of use', () {
    scenario(
      '80% then 25%',
      200,
      (r) => bernoulli(r, 119, (i) => i < 60 ? 0.8 : 0.25),
      effect,
    );
    scenario(
      '70% then 30%',
      200,
      (r) => bernoulli(r, 119, (i) => i < 60 ? 0.7 : 0.3),
      effect,
    );
    scenario(
      'taper 90% to 10%',
      200,
      (r) => bernoulli(r, 119, (i) => 0.9 - 0.8 * i / 119),
      effect,
    );
  });

  test('false refusals: even use, no effect, no trend', () {
    for (final int days in <int>[30, 60, 120, 365]) {
      for (final double p in <double>[0.15, 0.25, 0.5, 0.85, 0.92]) {
        scenario(
          'even $p over $days days',
          1000,
          (r) => bernoulli(r, days - 1, (_) => p),
          none,
        );
      }
    }
    scenario('episodic: 5% chance a day of a 4-day run, 120 days', 1000, (r) {
      final Set<int> d = episodes(r, 120, 0.05, 4);
      return d.length < 8 ? null : d;
    }, none);
    scenario(
      'episodic skips: used except 4-day runs starting on 5% of days, '
      '120 days',
      1000,
      (r) {
        final Set<int> skips = episodes(r, 120, 0.05, 4);
        final Set<int> d = <int>{
          for (int i = 0; i < 120; i++)
            if (!skips.contains(i) || i == 0 || i == 119) i,
        };
        return d;
      },
      none,
    );
  });

  test('power: even 50% over 60 days, effect -0.5 sd', () {
    scenario(
      'power',
      200,
      (r) => bernoulli(r, 59, (_) => 0.5),
      (i, used) => used ? -0.5 : 0,
    );
  });
}
