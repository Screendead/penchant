import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

import 'hours_after_synthetic.dart' show syntheticStart;

typedef ReplacementDays = ({List<HabitUse> uses, DateTime through});

int poisson(Random r, double rate) {
  final double limit = exp(-rate);
  int k = 0;
  for (double p = r.nextDouble(); p > limit; p *= r.nextDouble()) {
    k++;
  }
  return k;
}

/// [counts] entries of [habit] on each day from [syntheticStart], an amount
/// of one each, from 08:00.
List<HabitUse> usesOf(String habit, List<int> counts) => <HabitUse>[
  for (int i = 0; i < counts.length; i++)
    for (int k = 0; k < counts[i]; k++)
      HabitUse(
        habitId: habit,
        at: addDays(syntheticStart, i).add(Duration(minutes: 480 + 20 * k)),
        amount: 1,
      ),
];

/// [days] days of Cigarettes, a Poisson count a day at [fallFrom] until day
/// [fallAt] (null: never) and [fallTo] from it on, times [fallenShape] of
/// the day when given; and of Vape, [riser]'s count for each day, drawn from
/// a generator of its own so the two share nothing but the dates.
ReplacementDays replacementDays(
  int seed, {
  int days = 182,
  int? fallAt = 91,
  double fallFrom = 3,
  double fallTo = 1.5,
  double Function(int day)? fallenShape,
  required int Function(int day, Random r) riser,
}) {
  final Random a = Random(seed);
  final Random b = Random(seed * 7919 + 104729);
  return (
    uses: <HabitUse>[
      ...usesOf('Cigarettes', <int>[
        for (int i = 0; i < days; i++)
          poisson(
            a,
            (fallAt != null && i >= fallAt ? fallTo : fallFrom) *
                (fallenShape?.call(i) ?? 1),
          ),
      ]),
      ...usesOf('Vape', <int>[for (int i = 0; i < days; i++) riser(i, b)]),
    ],
    through: addDays(syntheticStart, days - 1),
  );
}
