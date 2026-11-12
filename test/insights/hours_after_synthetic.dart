import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/hours_after.dart' show wakingStepsKey;

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

/// In bed from 23:00 to 05:00 each night; heart rate every 5 minutes from
/// 05:00 to 23:00, HRV every 3 hours, and
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
  final List<HealthSample> bed = <HealthSample>[];
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
    bed.add(
      HealthSample(
        addDays(day, -1).add(const Duration(hours: 23)),
        day.add(const Duration(hours: 5)),
        0,
      ),
    );
  }
  return Synthetic(uses, <String, List<HealthSample>>{
    HealthSampleMetric.heartRate.id: heart,
    HealthSampleMetric.heartRateVariabilitySDNN.id: hrv,
    HealthSampleMetric.stepCount.id: steps,
    HealthSampleMetric.bed.id: bed,
  }, addDays(syntheticStart, days));
}

/// When a use falls on a day, in minutes after midnight, or null for none:
/// given the day's waking, whether a weekend, the day's wander (one value
/// per 5 minutes from midnight) and the day's draws.
typedef UsePolicy =
    int? Function(int wake, bool weekend, List<double> wander, Random r);

/// Whole days with sleep, for the hours-after comparisons' known traps. Heart
/// rate every [hrEvery] minutes around the clock, each dropped with chance
/// [dropReading]: asleep 52 plus a day level (sd 3) and half the wander;
/// awake 62, climbing 10 bpm over the 120 minutes after waking, plus the day
/// level, a wander (AR(1), 0.95 per 5 minutes, sd 1.5), 0.15 bpm per step a
/// minute and reading noise (sd 3). Waking is 06:30 (sd 20 min) on weekdays
/// and, with [weekendLieIn], 08:30 (sd 60) at weekends; bed at 23:00. Each
/// night is in [HealthSampleMetric.bed] unless dropped with chance
/// [missingNight], and with chance [splitNight] is two spans, up from 03:00
/// to 03:40. Two 15-minute walks a day at 100 steps a minute. Each of
/// [habits] is used once a day by its policy; [frequent] habits that many
/// times a day at random from 08:00 to 22:00. [effect] adds bpm at a number
/// of minutes after a use. With [stepLag], steps start from 0 up to that many
/// minutes after waking (a phone left on the nightstand), with 20 minutes of
/// getting up at 10 a minute, and half the nights hold a trip of 30 steps.
Synthetic wakingSynthetic(
  int seed, {
  int days = 120,
  int hrEvery = 5,
  double dropReading = 0,
  bool weekendLieIn = true,
  double missingNight = 0,
  double splitNight = 0,
  Map<String, UsePolicy> habits = const <String, UsePolicy>{},
  Map<String, int> frequent = const <String, int>{},
  double Function(String habit, int minutesAfter)? effect,
  int? stepLag,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<HealthSample> heart = <HealthSample>[];
  final List<HealthSample> steps = <HealthSample>[];
  final List<HealthSample> hrv = <HealthSample>[];
  final List<HealthSample> bed = <HealthSample>[];
  final List<String> names = habits.keys.toList()..sort();
  const int sleep = 23 * 60;
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(syntheticStart, i);
    final bool weekend = day.weekday >= 6;
    final int wake = weekend && weekendLieIn
        ? 510 + (60 * gaussian(r)).round()
        : 390 + (20 * gaussian(r)).round();
    final List<double> wander = List<double>.filled(1440 ~/ 5, 0);
    double w = 0;
    for (int k = 0; k < wander.length; k++) {
      w = 0.95 * w + 1.5 * sqrt(1 - 0.95 * 0.95) * gaussian(r);
      wander[k] = w;
    }
    final Map<String, List<int>> usedAt = <String, List<int>>{};
    for (final String name in names) {
      if (habits[name]!(wake, weekend, wander, r) case final int at) {
        usedAt[name] = <int>[at];
      }
    }
    frequent.forEach((name, n) {
      usedAt[name] = <int>[
        for (int k = 0; k < n; k++) 8 * 60 + r.nextInt(14 * 60),
      ];
    });
    usedAt.forEach((name, ats) {
      for (final int at in ats) {
        uses.add(
          HabitUse(
            habitId: name,
            at: day.add(Duration(minutes: at)),
            amount: 1,
          ),
        );
      }
    });
    final List<int> walks = <int>[
      for (int k = 0; k < 2; k++) wake + 60 + r.nextInt(12 * 60),
    ];
    final double level = 3 * gaussian(r);
    final int? firstStep = stepLag == null
        ? null
        : wake + r.nextInt(stepLag + 1);
    final int? trip = stepLag != null && r.nextBool()
        ? 60 + 5 * r.nextInt(48)
        : null;
    for (int m = 0; m < 1440; m += 5) {
      final bool awake = m >= wake && m < sleep;
      final double spm = !awake
          ? (trip != null && m == trip ? 6 : 0)
          : firstStep != null && m < firstStep
          ? 0
          : firstStep != null && m < firstStep + 20
          ? 10
          : walks.any((x) => m >= x && m < x + 15)
          ? 100
          : 3;
      double added = 0;
      if (effect != null) {
        usedAt.forEach((name, ats) {
          for (final int at in ats) {
            if (m >= at) added += effect(name, m - at);
          }
        });
      }
      final double hr = awake
          ? 62 +
                10 * min(1.0, (m - wake) / 120) +
                level +
                wander[m ~/ 5] +
                0.15 * spm +
                added
          : 52 + level + 0.5 * wander[m ~/ 5];
      final DateTime at = day.add(Duration(minutes: m));
      if (m % hrEvery == 0 && r.nextDouble() >= dropReading) {
        heart.add(HealthSample(at, at, hr + 3 * gaussian(r)));
      }
      steps.add(HealthSample(at, at.add(const Duration(minutes: 5)), 5 * spm));
      if (m % 180 == 0) hrv.add(HealthSample(at, at, 45 + 8 * gaussian(r)));
    }
    if (r.nextDouble() >= missingNight) {
      final DateTime from = addDays(day, -1).add(const Duration(hours: 23));
      final DateTime to = day.add(Duration(minutes: wake));
      if (r.nextDouble() < splitNight) {
        bed.add(HealthSample(from, day.add(const Duration(hours: 3)), 0));
        bed.add(HealthSample(day.add(const Duration(minutes: 220)), to, 0));
      } else {
        bed.add(HealthSample(from, to, 0));
      }
    }
  }
  uses.sort((a, b) => a.at.compareTo(b.at));
  return Synthetic(uses, <String, List<HealthSample>>{
    HealthSampleMetric.heartRate.id: heart,
    HealthSampleMetric.heartRateVariabilitySDNN.id: hrv,
    HealthSampleMetric.stepCount.id: steps,
    HealthSampleMetric.bed.id: bed,
    if (stepLag != null) wakingStepsKey: steps,
  }, addDays(syntheticStart, days));
}
