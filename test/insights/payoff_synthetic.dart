import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

import 'hours_after_synthetic.dart' show gaussian, syntheticStart;

typedef PayoffDays = ({
  List<HabitUse> uses,
  List<DailyOutcome> outcomes,
  DateTime through,
  DateTime? fallDay,
});

/// The three measures [payoffDays] writes.
const List<String> payoffMetrics = <String>[
  'sleepAsleep',
  'heartRateVariabilitySDNN',
  'restingHeartRate',
];

int _poisson(Random r, double rate) {
  final double limit = exp(-rate);
  int k = 0;
  for (double p = r.nextDouble(); p > limit; p *= r.nextDouble()) {
    k++;
  }
  return k;
}

/// [days] days of [habit], a Poisson count a day at [rateBefore] until day
/// [fallAt] (null: never) and [rateAfter] from it on, and three measures:
/// time asleep (420 min, sd 40), HRV (45 ms, sd 8) and resting heart rate
/// (58 bpm, sd 2).
///
/// Each measure's noise, in sd, is AR(1) at [ar], plus [drift] across the
/// [days], plus a year's sine of [season] amplitude at [seasonPhase] (a
/// fraction of the year at day 0; random when null), plus [wander] of an
/// AR(1) at 0.97. From [fallAt] on, [shift] sd is added to sleep and HRV and
/// taken off resting heart rate. A measure is missing on a day with chance
/// [missing].
PayoffDays payoffDays(
  int seed, {
  String habit = 'Coffee',
  int days = 182,
  int? fallAt = 91,
  double rateBefore = 3,
  double rateAfter = 1.5,
  double ar = 0,
  double drift = 0,
  double season = 0,
  double? seasonPhase,
  double wander = 0,
  double shift = 0,
  double missing = 0,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  final double fresh = sqrt(1 - ar * ar);
  final List<double> phase = <double>[
    for (int m = 0; m < 3; m++) seasonPhase ?? r.nextDouble(),
  ];
  final List<double> noise = List<double>.filled(3, 0);
  final List<double> slow = List<double>.filled(3, 0);
  const List<(double, double, double)> scale = <(double, double, double)>[
    (420, 40, 1),
    (45, 8, 1),
    (58, 2, -1),
  ];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(syntheticStart, i);
    final bool fallen = fallAt != null && i >= fallAt;
    final int count = _poisson(r, fallen ? rateAfter : rateBefore);
    for (int k = 0; k < count; k++) {
      uses.add(
        HabitUse(
          habitId: habit,
          at: day.add(Duration(minutes: 8 * 60 + 45 * k)),
          amount: 1,
        ),
      );
    }
    for (int m = 0; m < 3; m++) {
      noise[m] = ar * noise[m] + fresh * gaussian(r);
      slow[m] = 0.97 * slow[m] + sqrt(1 - 0.97 * 0.97) * gaussian(r);
      final double z =
          noise[m] +
          drift * i / days +
          season * sin(2 * pi * (i / 365 + phase[m])) +
          wander * slow[m];
      final bool gone = r.nextDouble() < missing;
      if (gone) continue;
      outcomes.add(
        DailyOutcome(
          date: day,
          metricId: payoffMetrics[m],
          value:
              scale[m].$1 +
              scale[m].$2 * (z + (fallen ? shift * scale[m].$3 : 0)),
        ),
      );
    }
  }
  return (
    uses: uses,
    outcomes: outcomes,
    through: addDays(syntheticStart, days - 1),
    fallDay: fallAt == null ? null : addDays(syntheticStart, fallAt),
  );
}
