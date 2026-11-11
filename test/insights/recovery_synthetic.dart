import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

import 'hours_after_synthetic.dart' show gaussian, syntheticStart;

typedef RecoveryDays = ({
  List<HabitUse> uses,
  List<DailyOutcome> outcomes,
  DateTime through,
});

/// The amount from which [recoveryDays] plants a heavy day's cost.
const int syntheticHeavyFrom = 5;

/// One sd of each measure [recoveryDays] writes, in its stored units.
const Map<String, double> syntheticSd = <String, double>{
  'sleepAsleep': 40,
  'heartRateVariabilitySDNN': 8,
  'restingHeartRate': 2,
};

/// Half an sd of each measure: the floor the synthetic checks judge "back"
/// within.
final Map<String, double> syntheticFloors = <String, double>{
  for (final MapEntry<String, double> e in syntheticSd.entries)
    e.key: e.value / 2,
};

/// [days] days of one habit, Beer, and three measures: time asleep (420 min,
/// sd 40, the night ending on the day), HRV (45 ms, sd 8) and resting heart
/// rate (58 bpm, sd 2), each AR(1) at [ar] in its noise and missing on a day
/// with chance [missing]. Beer is logged in the evening with chance 0.6, or
/// in runs with [runs] (0.8 after a day with it, 0.3 after one without), 1 to
/// 6 a day; a day with [syntheticHeavyFrom] or more is heavy.
///
/// [costs] is what a heavy day does, in sd, to each night after it in turn:
/// off sleep and HRV, onto resting heart rate; the day measures also take the
/// first of them on the heavy day itself. [anyUse] is the same cost for the
/// one night after any day of use, heavy or not. [reverse] is what a night
/// one sd short does to that day: that many more Beers. With [weekends],
/// Fridays and Saturdays always have Beer, 3 more of it, and the nights
/// ending on Saturday and Sunday run 0.75 sd long.
RecoveryDays recoveryDays(
  int seed, {
  int days = 120,
  double ar = 0,
  bool runs = false,
  List<double> costs = const <double>[],
  double anyUse = 0,
  double reverse = 0,
  bool weekends = false,
  double missing = 0,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  final double fresh = sqrt(1 - ar * ar);
  final List<bool> heavy = <bool>[];
  final List<bool> used = <bool>[];
  double sleep = 0, hrv = 0, resting = 0;
  double carried(int i, {required bool sameDay}) {
    double sum = 0;
    for (int k = 0; k < costs.length; k++) {
      final int at = i - k - 1;
      if (at >= 0 && heavy[at]) sum += costs[k];
    }
    if (sameDay && costs.isNotEmpty && heavy[i]) sum += costs.first;
    return sum;
  }

  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(syntheticStart, i);
    final bool usedBefore = i > 0 && used[i - 1];
    sleep = ar * sleep + fresh * gaussian(r);
    final double night =
        sleep -
        carried(i, sameDay: false) -
        (usedBefore ? anyUse : 0) +
        (weekends && day.weekday >= 6 ? 0.75 : 0);
    final bool party = weekends && (day.weekday == 5 || day.weekday == 6);
    final bool use =
        party || r.nextDouble() < (runs ? (usedBefore ? 0.8 : 0.3) : 0.6);
    final int amount = use
        ? max(1, (1 + r.nextInt(6) + (party ? 3 : 0) - reverse * night).round())
        : 0;
    used.add(use);
    heavy.add(amount >= syntheticHeavyFrom);
    hrv = ar * hrv + fresh * gaussian(r);
    resting = ar * resting + fresh * gaussian(r);
    final double dayCost =
        carried(i, sameDay: true) + (usedBefore ? anyUse : 0);
    for (final (String id, double mid, double z) in <(String, double, double)>[
      ('sleepAsleep', 420, night),
      ('heartRateVariabilitySDNN', 45, hrv - dayCost),
      ('restingHeartRate', 58, resting + dayCost),
    ]) {
      if (r.nextDouble() < missing) continue;
      outcomes.add(
        DailyOutcome(
          date: day,
          metricId: id,
          value: mid + syntheticSd[id]! * z,
        ),
      );
    }
    final int first = 18 * 60 + r.nextInt(90);
    for (int k = 0; k < amount; k++) {
      uses.add(
        HabitUse(
          habitId: 'Beer',
          at: day.add(Duration(minutes: first + 30 * k)),
          amount: 1,
        ),
      );
    }
  }
  return (
    uses: uses,
    outcomes: outcomes,
    through: addDays(syntheticStart, days - 1),
  );
}
