// Monte Carlo rates for the level-shift search in
// lib/insights/step_changes.dart and for the habit models that hold a shift
// fixed, on synthetic data only. Slow, so it lives outside test/:
//   flutter test tools/insights-calibration/step_changes_test.dart
// Each line prints one scenario's counts.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime january5 = DateTime(2026, 1, 5);

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

// [days] values of sd 1 around [level], each carrying [rho] of the one
// before; a share [missing] of the days has none.
void search(
  String name,
  int seeds, {
  int days = 120,
  double rho = 0,
  double missing = 0,
  double Function(int i)? level,
  int? planted,
}) {
  int any = 0, near = 0, shifts = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final Random r = Random(seed);
    double e = gaussian(r);
    final Map<DateTime, double> values = <DateTime, double>{};
    for (int i = 0; i < days; i++) {
      e = rho * e + sqrt(1 - rho * rho) * gaussian(r);
      if (r.nextDouble() < missing) continue;
      values[addDays(january5, i)] = (level?.call(i) ?? 0) + e;
    }
    final LevelShifts found = levelShifts(values);
    shifts += found.shifts.length;
    if (found.shifts.isNotEmpty) any++;
    if (planted != null &&
        found.shifts.any(
          (s) => daysBetween(addDays(january5, planted), s.at).abs() <= 5,
        )) {
      near++;
    }
  }
  stdout.writeln(
    '$name (n=$seeds): any shift $any, shifts $shifts'
    '${planted == null ? '' : ', within 5 days of the planted one $near'}',
  );
}

// Coffee every day, [amount] a day; the next day's outcome is [value] plus
// noise of sd 1.
void dose(
  String name,
  int seeds, {
  int days = 120,
  required int Function(Random r, int i) amount,
  required double Function(int i, int amount) value,
}) {
  final Map<String, int> counts = <String, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final Random r = Random(seed);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < days; i++) {
      final DateTime day = addDays(january5, i);
      final int a = amount(r, i);
      for (int k = 0; k < a; k++) {
        uses.add(
          HabitUse(
            habitId: 'Coffee',
            at: day.add(Duration(hours: 9, minutes: 90 * k)),
            amount: 1,
          ),
        );
      }
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: 'outcome',
          value: value(i, a) + gaussian(r),
        ),
      );
    }
    final HabitInsight result = doseFollows(
      habits: DailyHabitSeries.fromUses(uses),
      outcomes: OutcomeSeries.fromOutcomes(outcomes),
      metricId: 'outcome',
    ).single;
    final String key = switch (result) {
      HabitFinding() => 'finding',
      HabitRefusal(:final RefusalReason reason) => reason.name,
    };
    counts[key] = (counts[key] ?? 0) + 1;
  }
  stdout.writeln('$name (n=$seeds): $counts');
}

void main() {
  test('the search on noise', () {
    search('noise, 120 days', 500);
    search('noise, 365 days', 500, days: 365);
    search('noise, 120 days, 30% of days missing', 500, missing: 0.3);
    search('wandering (rho 0.4), 120 days', 500, rho: 0.4);
    search('wandering (rho 0.4), 365 days', 500, days: 365, rho: 0.4);
    search('wandering (rho 0.7), 365 days', 500, days: 365, rho: 0.7);
    search('drift of 2 sd over 120 days', 500, level: (i) => i / 60);
    search(
      'weekends 1 sd higher, 120 days',
      500,
      level: (i) => addDays(january5, i).weekday >= 6 ? 1 : 0,
    );
  });

  test('the search on a planted shift', () {
    for (final double size in <double>[0.5, 1, 2]) {
      search(
        'shift of $size sd at day 50 of 120',
        200,
        level: (i) => i < 50 ? 0 : size,
        planted: 50,
      );
    }
    search(
      'shift of 1 sd at day 50 of 120, rho 0.4',
      200,
      rho: 0.4,
      level: (i) => i < 50 ? 0 : 1,
      planted: 50,
    );
    search(
      'shift of 0.5 sd at day 180 of 365',
      200,
      days: 365,
      level: (i) => i < 180 ? 0 : 0.5,
      planted: 180,
    );
    search(
      '2 weeks 2 sd higher from day 60 of 120 (an illness)',
      200,
      level: (i) => i >= 60 && i < 74 ? 2 : 0,
      planted: 60,
    );
  });

  test('dose: amount and outcome change inside one month', () {
    for (final double size in <double>[0.5, 1, 2]) {
      dose(
        'amount 1-2 before day 50, 3-4 after; outcome steps $size sd at day '
        '50, no effect',
        500,
        amount: (r, i) => (i < 50 ? 1 : 3) + r.nextInt(2),
        value: (i, _) => i < 50 ? 0 : size,
      );
    }
    dose(
      'amount 1-4 throughout; outcome steps 1 sd at day 50, no effect',
      500,
      amount: (r, _) => 1 + r.nextInt(4),
      value: (i, _) => i < 50 ? 0 : 1,
    );
  });

  test('dose: a real effect', () {
    dose(
      'amount 1-4 throughout, 0.2 sd per unit, no shift',
      200,
      amount: (r, _) => 1 + r.nextInt(4),
      value: (_, a) => -0.2 * a,
    );
    dose(
      'amount 1-4 throughout, 0.2 sd per unit; outcome also steps 1 sd at '
      'day 50',
      200,
      amount: (r, _) => 1 + r.nextInt(4),
      value: (i, a) => -0.2 * a + (i < 50 ? 0 : 1),
    );
    dose(
      'amount 1-2 before day 50, 3-4 after, 0.5 sd per unit and nothing '
      'else',
      200,
      amount: (r, i) => (i < 50 ? 1 : 3) + r.nextInt(2),
      value: (_, a) => -0.5 * a,
    );
  });
}
