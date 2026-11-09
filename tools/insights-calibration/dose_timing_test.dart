// Monte Carlo rates for the dose and time-of-last-use comparisons in
// lib/insights/what_follows.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/dose_timing_test.dart
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

typedef Day = ({int index, DateTime day, int amount, int lastMinutes});

// One habit's day: [amount] entries of 1, 90 minutes apart, the last at
// [lastMinutes] after midnight.
List<HabitUse> dayOfUse(
  String habit,
  DateTime day,
  int amount,
  int lastMinutes,
) => <HabitUse>[
  for (int k = 0; k < amount; k++)
    HabitUse(
      habitId: habit,
      at: day.add(Duration(minutes: lastMinutes - 90 * (amount - 1 - k))),
      amount: 1,
    ),
];

typedef Judge =
    List<HabitInsight> Function({
      required DailyHabitSeries habits,
      required OutcomeSeries outcomes,
      required String metricId,
      int lagDays,
      DateTime? from,
      DateTime? through,
      InsightGates gates,
    });

// Coffee on every one of [days] days (or those [used] keeps), [amount] a day
// with the last at [last]; the next day's outcome is [value] plus noise of
// sd 1.
void scenario(
  String name,
  Judge judge,
  int seeds, {
  int days = 120,
  bool Function(Random r, int i)? used,
  int Function(Random r, int i)? amount,
  int Function(Random r, int i)? last,
  double Function(Day d)? value,
}) {
  final Map<String, int> counts = <String, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final Random random = Random(seed);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < days; i++) {
      final DateTime day = addDays(january5, i);
      final int a = amount?.call(random, i) ?? 1 + random.nextInt(4);
      final int l = last?.call(random, i) ?? 12 * 60 + random.nextInt(11 * 60);
      final bool on =
          i == 0 || i == days - 1 || (used?.call(random, i) ?? true);
      if (on) uses.addAll(dayOfUse('Coffee', day, a, l));
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: metric,
          value:
              (on
                  ? value?.call((
                          index: i,
                          day: day,
                          amount: a,
                          lastMinutes: l,
                        )) ??
                        0
                  : 0) +
              gaussian(random),
        ),
      );
    }
    final HabitInsight r = judge(
      habits: DailyHabitSeries.fromUses(uses),
      outcomes: OutcomeSeries.fromOutcomes(outcomes),
      metricId: metric,
    ).single;
    final String key = switch (r) {
      HabitFinding() => 'finding',
      HabitRefusal(:final RefusalReason reason) => reason.name,
    };
    counts[key] = (counts[key] ?? 0) + 1;
  }
  stdout.writeln('$name (n=$seeds): $counts');
}

final List<String> outcomeIds = <String>[for (int k = 0; k < 9; k++) 'm$k'];

// The whole page on noise: Coffee and Tea on a fair coin's days, Water every
// day, 1 to 4 a day, the last between 12:00 and 01:00; nine outcomes of noise.
void page(int seeds) {
  int checks = 0, raw = 0, rawReports = 0, after = 0, reports = 0;
  final Map<InsightKind, int> rawByKind = <InsightKind, int>{};
  final Map<InsightKind, int> checksByKind = <InsightKind, int>{};
  final Map<InsightKind, int> afterByKind = <InsightKind, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final Random random = Random(seed);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < 120; i++) {
      final DateTime day = addDays(january5, i);
      for (final String habit in <String>['Coffee', 'Tea', 'Water']) {
        if (habit != 'Water' && random.nextBool()) continue;
        uses.addAll(
          dayOfUse(
            habit,
            day,
            1 + random.nextInt(4),
            12 * 60 + random.nextInt(13 * 60),
          ),
        );
      }
      for (final String m in outcomeIds) {
        outcomes.add(
          DailyOutcome(
            date: addDays(day, 1),
            metricId: m,
            value: gaussian(random),
          ),
        );
      }
    }
    final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
    final OutcomeSeries series = OutcomeSeries.fromOutcomes(outcomes);
    final List<HabitInsight> all = <HabitInsight>[
      for (final String m in outcomeIds)
        for (final Judge judge in <Judge>[
          whatFollows,
          doseFollows,
          lastUseFollows,
        ])
          ...judge(habits: habits, outcomes: series, metricId: m),
    ];
    for (final HabitInsight i in all) {
      final bool tested = switch (i) {
        HabitFinding() => true,
        HabitRefusal(:final double? pValue) => pValue != null,
      };
      if (!tested) continue;
      checks++;
      checksByKind[i.kind] = (checksByKind[i.kind] ?? 0) + 1;
      if (i is HabitFinding) {
        raw++;
        rawByKind[i.kind] = (rawByKind[i.kind] ?? 0) + 1;
      }
    }
    if (all.any((i) => i is HabitFinding)) rawReports++;
    final List<HabitFinding> kept = controlFalseDiscoveries(
      all,
    ).whereType<HabitFinding>().toList();
    for (final HabitFinding f in kept) {
      afterByKind[f.kind] = (afterByKind[f.kind] ?? 0) + 1;
    }
    after += kept.length;
    if (kept.isNotEmpty) reports++;
  }
  stdout
    ..writeln(
      'page on noise (n=$seeds): checks=$checks raw=$raw '
      '(${(100 * raw / checks).toStringAsFixed(2)}%) '
      'rawReports=$rawReports after=$after '
      '(${(100 * after / checks).toStringAsFixed(2)}%) reports=$reports '
      '(${(100 * reports / seeds).toStringAsFixed(1)}%)',
    )
    ..writeln(
      '  by kind: checks=$checksByKind raw=$rawByKind after=$afterByKind',
    );
}

void main() {
  test('noise alone, one check', () {
    scenario('dose, daily, 1-4 a day', doseFollows, 1000);
    scenario('time, daily, 12:00-23:00', lastUseFollows, 1000);
    scenario(
      'time, daily, 18:00-03:00 (past the cut-off)',
      lastUseFollows,
      1000,
      last: (r, _) => 18 * 60 + r.nextInt(9 * 60),
    );
    scenario(
      'dose, half the days',
      doseFollows,
      1000,
      used: (r, _) => r.nextBool(),
    );
  });

  test('power', () {
    for (final double effect in <double>[0.1, 0.2, 0.4]) {
      scenario(
        'dose, daily, $effect sd per unit',
        doseFollows,
        200,
        value: (d) => -effect * d.amount,
      );
    }
    for (final double effect in <double>[0.05, 0.1, 0.2]) {
      scenario(
        'time, daily, $effect sd per hour',
        lastUseFollows,
        200,
        value: (d) => -effect * d.lastMinutes / 60,
      );
    }
    scenario(
      'dose, daily, 0.2 sd per unit, 60 days',
      doseFollows,
      200,
      days: 60,
      value: (d) => -0.2 * d.amount,
    );
  });

  test('confounds with the months', () {
    // Amount rises month by month, outcome steps up with each month.
    scenario(
      'dose: amount = month + 0-2, outcome steps 1 sd a month',
      doseFollows,
      500,
      amount: (r, i) => addDays(january5, i).month + r.nextInt(3),
      value: (d) => d.day.month.toDouble(),
    );
    scenario(
      'dose: amount = month (no spread within), outcome steps 1 sd a month',
      doseFollows,
      500,
      amount: (r, i) => addDays(january5, i).month,
      value: (d) => d.day.month.toDouble(),
    );
    scenario(
      'time: last use 1 h later each month (+0-3 h), outcome steps 1 sd a '
      'month',
      lastUseFollows,
      500,
      last: (r, i) =>
          (14 + addDays(january5, i).month) * 60 + r.nextInt(3 * 60),
      value: (d) => d.day.month.toDouble(),
    );
    // The month terms do not cover a step inside a month.
    scenario(
      'dose: amount 1-2 before day 50, 3-4 after; outcome steps 1 sd at day '
      '50 (mid-February)',
      doseFollows,
      500,
      amount: (r, i) => (i < 50 ? 1 : 3) + r.nextInt(2),
      value: (d) => d.index < 50 ? 0 : 1,
    );
  });

  test('steady gates', () {
    scenario(
      'dose: 1 a day, 2 on 5% of days',
      doseFollows,
      200,
      amount: (r, _) => r.nextDouble() < 0.05 ? 2 : 1,
    );
    scenario(
      'dose: 1 or 2 a day',
      doseFollows,
      200,
      amount: (r, _) => 1 + r.nextInt(2),
    );
    scenario(
      'dose: 1 to 3 a day',
      doseFollows,
      200,
      amount: (r, _) => 1 + r.nextInt(3),
    );
    scenario(
      'time: within 40 minutes',
      lastUseFollows,
      200,
      last: (r, _) => 20 * 60 + r.nextInt(40),
    );
    scenario(
      'time: within 3 hours',
      lastUseFollows,
      200,
      last: (r, _) => 19 * 60 + r.nextInt(180),
    );
  });

  // One day far from the rest, with a night 3 sd off after it: the
  // leave-one-out check is what keeps these near the noise rate.
  test('one extreme day', () {
    scenario(
      'dose: one day of 12 against 1-4, outcome +3 sd after it',
      doseFollows,
      400,
      amount: (r, i) => i == 75 ? 12 : 1 + r.nextInt(4),
      value: (d) => d.index == 75 ? 3 : 0,
    );
    scenario(
      'time: one day whose only use is at 06:00 against 19:00-24:00, '
      'outcome +3 sd after it',
      lastUseFollows,
      400,
      amount: (r, i) => i == 75 ? 1 : 1 + r.nextInt(2),
      last: (r, i) => i == 75 ? 6 * 60 : 19 * 60 + r.nextInt(5 * 60),
      value: (d) => d.index == 75 ? 3 : 0,
    );
  });

  test('the page on noise, every kind in one family', () {
    page(400);
  });
}
