import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

import 'hours_after_synthetic.dart' show gaussian, syntheticStart;

typedef BeforeDays = ({
  List<HabitUse> uses,
  List<DailyOutcome> outcomes,
  DateTime through,
});

/// [days] days of one habit, Coffee, and three measures: time asleep (420
/// min, sd 40, the night ending on the day), HRV (45 ms, sd 8) and resting
/// heart rate (58 bpm, sd 2), each AR(1) at [ar] in its noise. Waking is
/// 07:00 (sd 30 min), with [wakeLinked] of each minute later added to the
/// night's sleep. Coffee is used with chance 0.5, or in runs with [runs]
/// (0.75 after a day with it, 0.25 after one without), 1 to 4 a day, first
/// at waking plus 30 to 270 minutes.
///
/// [forward] is the cost of a day's use, in sd: off that night's sleep and
/// that day's HRV, onto that day's resting heart rate. [reverse] is what a
/// night one sd short does to the day: [reverse] / 4 more chance of use,
/// [reverse] more of it and [reverse] hours earlier.
BeforeDays beforeDays(
  int seed, {
  int days = 120,
  double ar = 0,
  bool runs = false,
  double forward = 0,
  double reverse = 0,
  double wakeLinked = 0,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  final double fresh = sqrt(1 - ar * ar);
  double sleep = 0, hrv = 0, resting = 0;
  bool usedBefore = false;
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(syntheticStart, i);
    final double wake = 30 * gaussian(r);
    sleep = ar * sleep + fresh * gaussian(r);
    final double night =
        sleep - (usedBefore ? forward : 0) + wakeLinked * wake / 40;
    final double chance =
        (runs ? (usedBefore ? 0.75 : 0.25) : 0.5) - reverse * night / 4;
    final bool used = r.nextDouble() < chance;
    hrv = ar * hrv + fresh * gaussian(r);
    resting = ar * resting + fresh * gaussian(r);
    outcomes
      ..add(
        DailyOutcome(date: day, metricId: 'sleepAsleep', value: 420 + 40 * night),
      )
      ..add(
        DailyOutcome(date: day, metricId: 'sleepEnd', value: 19 * 60 + wake),
      )
      ..add(
        DailyOutcome(
          date: day,
          metricId: 'heartRateVariabilitySDNN',
          value: 45 + 8 * (hrv - (used ? forward : 0)),
        ),
      )
      ..add(
        DailyOutcome(
          date: day,
          metricId: 'restingHeartRate',
          value: 58 + 2 * (resting + (used ? forward : 0)),
        ),
      );
    if (used) {
      final int amount = max(
        1,
        (1 + r.nextInt(4) - reverse * night).round(),
      );
      final int first = (7 * 60 + wake + 30 + r.nextInt(240) + 60 * reverse * night)
          .round()
          .clamp(5 * 60 + 1, 20 * 60);
      for (int k = 0; k < amount; k++) {
        uses.add(
          HabitUse(
            habitId: 'Coffee',
            at: day.add(Duration(minutes: first + 45 * k)),
            amount: 1,
          ),
        );
      }
    }
    usedBefore = used;
  }
  return (
    uses: uses,
    outcomes: outcomes,
    through: addDays(syntheticStart, days - 1),
  );
}
