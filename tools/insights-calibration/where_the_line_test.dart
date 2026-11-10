// Monte Carlo rates for the line in an amount and the cut-off time for the
// last use (doseLineFollows, lastUseLineFollows in
// lib/insights/what_follows.dart), on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/where_the_line_test.dart
// Each line prints one scenario: findings and each refusal reason, how many
// results had a p-value under 0.05 before it was multiplied by the cuts tried
// (what picking the best cut would report uncorrected), and the cuts chosen
// among the findings.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

const String metric = 'outcome';
final DateTime january5 = DateTime(2026, 1, 5);

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

typedef Day = ({int index, DateTime day, int amount, int lastMinutes});

List<HabitUse> dayOfUse(
  String habit,
  DateTime day,
  int amount,
  int lastMinutes,
) => <HabitUse>[
  for (int k = 0; k < amount; k++)
    HabitUse(
      habitId: habit,
      // By the wall clock, so a daylight-saving day moves no use.
      at: DateTime(
        day.year,
        day.month,
        day.day,
        0,
        lastMinutes - 90 * (amount - 1 - k),
      ),
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

// Coffee on every one of [days] days, [amount] a day (1 to 4 unless given)
// with the last at [last] (12:00 to 23:00 unless given); the next day's
// outcome is [value] plus noise of sd 1. [cuts] is how many cuts the grid
// holds in this scenario, to undo the correction for the uncorrected count.
void scenario(
  String name,
  Judge judge,
  int seeds, {
  required int cuts,
  int days = 120,
  InsightGates gates = const InsightGates(),
  int Function(Random r, int i)? amount,
  int Function(Random r, int i)? last,
  double Function(Day d)? value,
}) {
  final Map<String, int> counts = <String, int>{};
  final Map<double, int> chosen = <double, int>{};
  int uncorrected = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final Random random = Random(seed);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < days; i++) {
      final DateTime day = addDays(january5, i);
      final int a = amount?.call(random, i) ?? 1 + random.nextInt(4);
      final int l = last?.call(random, i) ?? 12 * 60 + random.nextInt(11 * 60);
      uses.addAll(dayOfUse('Coffee', day, a, l));
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: metric,
          value:
              (value?.call((index: i, day: day, amount: a, lastMinutes: l)) ??
                  0) +
              gaussian(random),
        ),
      );
    }
    final HabitInsight r = judge(
      habits: DailyHabitSeries.fromUses(uses),
      outcomes: OutcomeSeries.fromOutcomes(outcomes),
      metricId: metric,
      gates: gates,
    ).single;
    final String key = switch (r) {
      HabitFinding() => 'finding',
      HabitRefusal(:final RefusalReason reason) => reason.name,
    };
    counts[key] = (counts[key] ?? 0) + 1;
    final double? p = switch (r) {
      HabitFinding(:final double pValue) => pValue,
      HabitRefusal(:final double? pValue) => pValue,
    };
    if (p != null && p / cuts < 0.05) uncorrected++;
    if (r is HabitFinding) chosen[r.cut!] = (chosen[r.cut!] ?? 0) + 1;
  }
  stdout.writeln(
    '$name (n=$seeds): $counts; p under 0.05 before the correction: '
    '$uncorrected; cuts found: $chosen',
  );
}

final List<String> outcomeIds = <String>[for (int k = 0; k < 9; k++) 'm$k'];

// The whole page on noise, as dose_timing_test.dart's with the two line
// comparisons in the family: Coffee and Tea on a fair coin's days, Water
// every day, 1 to 4 a day, the last between 12:00 and 01:00; nine outcomes of
// noise.
void page(int seeds) {
  int checks = 0, raw = 0, rawReports = 0, after = 0, reports = 0, shown = 0;
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
          doseLineFollows,
          lastUseLineFollows,
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
    shown += oneOfSlopeAndLine(kept).length;
    if (kept.isNotEmpty) reports++;
  }
  String name(Map<InsightKind, int> m) => <String, int>{
    for (final MapEntry<InsightKind, int> e in m.entries) e.key.name: e.value,
  }.toString();
  stdout
    ..writeln(
      'page on noise (n=$seeds): checks=$checks raw=$raw '
      '(${(100 * raw / checks).toStringAsFixed(2)}%) '
      'rawReports=$rawReports after=$after '
      '(${(100 * after / checks).toStringAsFixed(2)}%) reports=$reports '
      '(${(100 * reports / seeds).toStringAsFixed(1)}%) '
      'shown after one of slope and line=$shown',
    )
    ..writeln(
      '  by kind: checks=${name(checksByKind)} raw=${name(rawByKind)} '
      'after=${name(afterByKind)}',
    );
}

void main() {
  // 1 to 4 a day leaves the cuts 2, 3 and 4; a last use from 12:00 to 23:00
  // has 13:00 to 22:00 or 23:00, thinned to 5.
  test('noise alone, one check', () {
    scenario('amount line, 1-4 a day', doseLineFollows, 1000, cuts: 3);
    scenario(
      'amount line, 1-4 a day, one cut only (no search)',
      doseLineFollows,
      1000,
      cuts: 1,
      gates: const InsightGates(maxCuts: 1),
    );
    scenario(
      'amount line, 1-8 a day',
      doseLineFollows,
      1000,
      cuts: 5,
      amount: (r, _) => 1 + r.nextInt(8),
    );
    scenario('time cut-off, 12:00-23:00', lastUseLineFollows, 1000, cuts: 5);
    scenario(
      'time cut-off, 12:00-23:00, one cut only (no search)',
      lastUseLineFollows,
      1000,
      cuts: 1,
      gates: const InsightGates(maxCuts: 1),
    );
    scenario(
      'time cut-off, 18:00-03:00 (past midnight)',
      lastUseLineFollows,
      1000,
      cuts: 5,
      last: (r, _) => 18 * 60 + r.nextInt(9 * 60),
    );
    scenario('amount line, 60 days', doseLineFollows, 1000, cuts: 3, days: 60);
  });

  test('power on a planted line', () {
    for (final double effect in <double>[0.4, 0.6, 0.8]) {
      scenario(
        'amount: $effect sd from 3 a day (half the days)',
        doseLineFollows,
        200,
        cuts: 3,
        value: (d) => d.amount >= 3 ? -effect : 0,
      );
    }
    scenario(
      'amount: 0.8 sd from 4 a day (a quarter of the days)',
      doseLineFollows,
      200,
      cuts: 3,
      value: (d) => d.amount >= 4 ? -0.8 : 0,
    );
    scenario(
      'amount: 0.8 sd from 3 a day, 60 days',
      doseLineFollows,
      200,
      cuts: 3,
      days: 60,
      value: (d) => d.amount >= 3 ? -0.8 : 0,
    );
    for (final double effect in <double>[0.6, 0.8]) {
      scenario(
        'time: $effect sd from 18:00 (not on the grid of 13, 15, 18, 20, 22 '
        'unless 13:00 has its days: nearest is found)',
        lastUseLineFollows,
        200,
        cuts: 5,
        value: (d) => d.lastMinutes >= 18 * 60 ? -effect : 0,
      );
    }
    scenario(
      'time: 0.8 sd from 15:00 (a quarter of the days before it)',
      lastUseLineFollows,
      200,
      cuts: 5,
      value: (d) => d.lastMinutes >= 15 * 60 ? -0.8 : 0,
    );
  });

  // A straight-line effect has no line in it; the step still fires, and the
  // report shows whichever of slope and step has the smaller p-value.
  test('a straight-line effect', () {
    scenario(
      'amount line on 0.3 sd per unit',
      doseLineFollows,
      200,
      cuts: 3,
      value: (d) => -0.3 * d.amount,
    );
    scenario(
      'time cut-off on 0.1 sd per hour',
      lastUseLineFollows,
      200,
      cuts: 5,
      value: (d) => -0.1 * d.lastMinutes / 60,
    );
    for (final (String name, double Function(Day d) value)
        in <(String, double Function(Day d))>[
          ('0.3 sd per unit', (d) => -0.3 * d.amount),
          ('0.8 sd from 3 a day', (d) => d.amount >= 3 ? -0.8 : 0),
        ]) {
      int slope = 0, line = 0, neither = 0;
      for (int seed = 0; seed < 200; seed++) {
        final Random random = Random(seed);
        final List<HabitUse> uses = <HabitUse>[];
        final List<DailyOutcome> outcomes = <DailyOutcome>[];
        for (int i = 0; i < 120; i++) {
          final DateTime day = addDays(january5, i);
          final int a = 1 + random.nextInt(4);
          uses.addAll(dayOfUse('Coffee', day, a, 20 * 60));
          outcomes.add(
            DailyOutcome(
              date: addDays(day, 1),
              metricId: metric,
              value:
                  value((index: i, day: day, amount: a, lastMinutes: 1200)) +
                  gaussian(random),
            ),
          );
        }
        final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
        final OutcomeSeries series = OutcomeSeries.fromOutcomes(outcomes);
        final List<HabitFinding> shown = oneOfSlopeAndLine(<HabitFinding>[
          for (final Judge judge in <Judge>[doseFollows, doseLineFollows])
            ...judge(
              habits: habits,
              outcomes: series,
              metricId: metric,
            ).whereType<HabitFinding>(),
        ]);
        if (shown.isEmpty) {
          neither++;
        } else if (shown.single.kind == InsightKind.dose) {
          slope++;
        } else {
          line++;
        }
      }
      stdout.writeln(
        'which shows, $name (n=200): slope=$slope line=$line neither=$neither',
      );
    }
  });

  // The month terms do not cover a change inside a month, and a 0/1 column
  // matches a step in the outcome best of all.
  test('confounds with time', () {
    scenario(
      'amount = month + 0-2, outcome steps 1 sd a month',
      doseLineFollows,
      500,
      cuts: 5,
      amount: (r, i) => addDays(january5, i).month + r.nextInt(3),
      value: (d) => d.day.month.toDouble(),
    );
    scenario(
      'amount 1-2 before day 50, 3-4 after; outcome steps 1 sd at day 50 '
      '(mid-February)',
      doseLineFollows,
      500,
      cuts: 3,
      amount: (r, i) => (i < 50 ? 1 : 3) + r.nextInt(2),
      value: (d) => d.index < 50 ? 0 : 1,
    );
  });

  test('the page on noise, every kind in one family', () {
    page(400);
  });
}
