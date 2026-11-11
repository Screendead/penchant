import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart';

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

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

/// Eight hours in bed ending [minutes] after [day]'s midnight.
HealthSample nightEnding(DateTime day, num minutes) {
  final DateTime end = useAt('', day, minutes).at;
  return HealthSample(end.subtract(const Duration(hours: 8)), end, 0);
}

/// [days] days from [followsStart], waking at 07:30 give or take an hour
/// (sd): Coffee 5 to 20 minutes after waking, a Cigarette 5 to 40 minutes
/// after, each on its own, and six more Cigarettes through the rest of the
/// 16 hours awake. [woke] is told each day's waking, in minutes.
List<HabitUse> bothAfterWaking(
  Random r,
  int days,
  void Function(DateTime day, double minutes) woke,
) {
  final List<HabitUse> uses = <HabitUse>[];
  for (int d = 0; d < days; d++) {
    final DateTime day = addDays(followsStart, d);
    final double wake = 7.5 * 60 + 60 * gaussian(r);
    woke(day, wake);
    uses.add(useAt('coffee', day, wake + 5 + r.nextDouble() * 15));
    uses.add(useAt('cigarettes', day, wake + 5 + r.nextDouble() * 35));
    for (int k = 0; k < 6; k++) {
      uses.add(
        useAt('cigarettes', day, wake + 60 + r.nextDouble() * 15 * 60),
      );
    }
  }
  return uses;
}
