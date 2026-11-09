import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart';

// Synthetic days for the hours-after comparisons, shared with
// tools/insights-calibration/hours_after_test.dart. No real Health data.

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

/// When a habit is used: on a day with [chance], once, at a minute after
/// midnight from [from] up to [to].
typedef HabitPattern = ({double chance, int from, int to});

class Synthetic {
  const Synthetic(this.uses, this.samples, this.through);

  final List<HabitUse> uses;
  final Map<String, List<HealthSample>> samples;

  /// The day after the last.
  final DateTime through;
}

final DateTime syntheticStart = DateTime(2026, 3, 2);

/// Heart rate every 5 minutes from 05:00 to 23:00, HRV every 3 hours, and
/// steps in 5-minute counts. Heart rate is 60, plus [morningRise] bpm climbed
/// evenly from 05:00 to 11:00 and held to 18:00, then eased off; plus a day
/// level (sd 3), a slow wander within the day (AR(1), 0.95, sd 1.5) and
/// reading noise (sd 3); plus 0.15 bpm per step a minute. Steps are 3 a
/// minute, with two 15-minute walks a day at 100 a minute at random times, and one
/// starting at each Coffee with chance [walkAfterCoffee]. [effect] adds bpm
/// at a number of minutes after a use of a habit.
Synthetic synthetic(
  int seed, {
  int days = 120,
  Map<String, HabitPattern> habits = const <String, HabitPattern>{
    'Coffee': (chance: 0.6, from: 6 * 60, to: 11 * 60),
  },
  double morningRise = 16,
  double walkAfterCoffee = 0,
  double Function(String habit, int minutesAfter)? effect,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<HealthSample> heart = <HealthSample>[];
  final List<HealthSample> hrv = <HealthSample>[];
  final List<HealthSample> steps = <HealthSample>[];
  final List<String> names = habits.keys.toList()..sort();
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(syntheticStart, i);
    final Map<String, int> usedAt = <String, int>{};
    for (final String name in names) {
      final HabitPattern p = habits[name]!;
      if (r.nextDouble() < p.chance) {
        final int at = p.from + r.nextInt(p.to - p.from);
        usedAt[name] = at;
        uses.add(
          HabitUse(
            habitId: name,
            at: day.add(Duration(minutes: at)),
            amount: 1,
          ),
        );
      }
    }
    final List<int> walks = <int>[
      for (int k = 0; k < 2; k++) 6 * 60 + r.nextInt(16 * 60),
      if (usedAt['Coffee'] case final int c
          when r.nextDouble() < walkAfterCoffee)
        c,
    ];
    double spm(int m) => walks.any((w) => m >= w && m < w + 15) ? 100 : 3;
    final double dayLevel = 3 * gaussian(r);
    double wander = 0;
    for (int m = 5 * 60; m < 23 * 60; m += 5) {
      wander = 0.95 * wander + 1.5 * sqrt(1 - 0.95 * 0.95) * gaussian(r);
      final double rise = m < 11 * 60
          ? morningRise * (m - 300) / 360
          : m < 18 * 60
          ? morningRise
          : morningRise * (1 - (m - 18 * 60) / 600);
      double added = 0;
      if (effect != null) {
        for (final MapEntry<String, int> u in usedAt.entries) {
          if (m >= u.value) added += effect(u.key, m - u.value);
        }
      }
      final DateTime at = day.add(Duration(minutes: m));
      heart.add(
        HealthSample(
          at,
          at,
          60 +
              rise +
              dayLevel +
              wander +
              3 * gaussian(r) +
              0.15 * spm(m) +
              added,
        ),
      );
      steps.add(
        HealthSample(at, at.add(const Duration(minutes: 5)), 5 * spm(m)),
      );
      if (m % 180 == 0) hrv.add(HealthSample(at, at, 45 + 8 * gaussian(r)));
    }
  }
  return Synthetic(uses, <String, List<HealthSample>>{
    HealthSampleMetric.heartRate.id: heart,
    HealthSampleMetric.heartRateVariabilitySDNN.id: hrv,
    HealthSampleMetric.stepCount.id: steps,
  }, addDays(syntheticStart, days));
}
