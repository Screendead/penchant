import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

final DateTime followsStart = DateTime(2026, 1, 5);

// By the wall clock, so a daylight-saving day moves no use.
HabitUse useAt(String habit, DateTime day, num minutes) => HabitUse(
  habitId: habit,
  at: DateTime(day.year, day.month, day.day, 0, 0, (minutes * 60).round()),
  amount: 1,
);

/// [days] days from [followsStart]: Coffee twice between 07:00 and 12:00,
/// Cigarettes six times between 07:00 and 23:00 at times of their own, and
/// after a share [follow] of the Coffees one more, 3 to 12 minutes later.
List<HabitUse> coffeeThenCigarettes(
  int seed, {
  int days = 120,
  double follow = 0,
}) {
  final Random r = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  for (int d = 0; d < days; d++) {
    final DateTime day = addDays(followsStart, d);
    for (int k = 0; k < 2; k++) {
      final double at = 7 * 60 + r.nextDouble() * 300;
      uses.add(useAt('coffee', day, at));
      if (r.nextDouble() < follow) {
        uses.add(useAt('cigarettes', day, at + 3 + r.nextDouble() * 9));
      }
    }
    for (int k = 0; k < 6; k++) {
      uses.add(useAt('cigarettes', day, 7 * 60 + r.nextDouble() * 960));
    }
  }
  return uses;
}
