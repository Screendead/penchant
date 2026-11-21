import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
const int days = 120;
const String deep = 'sleepDeep';

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

typedef Day = ({int index, int amount, int lastMinutes});

// Coffee every day of [days]: [amountOf] entries of 1 (1 to 4 unless given),
// 90 minutes apart, the last at [lastOf] (18:00 to 23:00 unless given); the
// next night's deep sleep is [value] of that day plus noise of sd 10.
InsightsInput dailyCoffee(
  int seed,
  double Function(Day d) value, {
  int Function(Random random, int index)? amountOf,
  int Function(Random random, int index)? lastOf,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final int amount = amountOf?.call(random, i) ?? 1 + random.nextInt(4);
    final int last = lastOf?.call(random, i) ?? 18 * 60 + random.nextInt(300);
    for (int k = 0; k < amount; k++) {
      uses.add(
        HabitUse(
          habitId: 'Coffee',
          // By the wall clock, so a daylight-saving day moves no use.
          at: DateTime(
            day.year,
            day.month,
            day.day,
            0,
            last - 90 * (amount - 1 - k),
          ),
          amount: 1,
        ),
      );
    }
    outcomes.add(
      DailyOutcome(
        date: addDays(day, 1),
        metricId: deep,
        value:
            value((index: i, amount: amount, lastMinutes: last)) +
            10 * gaussian(random),
      ),
    );
  }
  return InsightsInput(
    uses: uses,
    outcomes: outcomes,
    from: start,
    through: addDays(start, days),
  );
}

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

HabitInsight judged(
  Judge judge,
  InsightsInput input, {
  InsightGates gates = const InsightGates(),
}) => judge(
  habits: DailyHabitSeries.fromUses(input.uses),
  outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
  metricId: deep,
  gates: gates,
).single;

double? pValueOf(HabitInsight insight) => switch (insight) {
  HabitFinding(:final double pValue) => pValue,
  HabitRefusal(:final double? pValue) => pValue,
};

HabitFinding finding(
  InsightKind kind,
  double cut, {
  String metricId = deep,
  double pValue = 0.001,
}) => HabitFinding(
  habitId: 'coffee',
  metricId: metricId,
  lagDays: 1,
  usableDays: 120,
  exposedDays: 41,
  raw: null,
  kind: kind,
  step: kind == InsightKind.lastUse ? 60 : 1,
  cut: kind == InsightKind.doseLine || kind == InsightKind.lastUseLine
      ? cut
      : null,
  effect: -14,
  interval: const stats.Interval(-21, -7),
  standardized: -0.5,
  pValue: pValue,
);

void main() {
  group('a line in the amount', () {
    test('is found where it was drawn, with the days at or over it', () {
      for (int seed = 0; seed < 20; seed++) {
        final InsightsInput input = dailyCoffee(
          seed,
          (d) => 80.0 - (d.amount >= 3 ? 20 : 0),
        );
        final HabitInsight line = judged(doseLineFollows, input);
        expect(line, isA<HabitFinding>(), reason: 'seed $seed');
        line as HabitFinding;
        expect(line.kind, InsightKind.doseLine);
        expect(line.cut, 3);
        expect(line.effect, inInclusiveRange(-28, -12));
        expect(line.interval.high, lessThan(0));
        expect(line.usableDays, days);
        final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
        expect(
          line.exposedDays,
          <int>[
            for (int i = 0; i < days; i++)
              if (habits.lateDayTotal('Coffee', addDays(start, i)) >= 3) i,
          ].length,
        );
        // The two sides as they are, so the floor is not scaled by a spread.
        expect(line.spread, isNull);
      }
    });

    test('with one place to draw it, is judged as one comparison: the '
        'slope’s own result', () {
      final InsightsInput input = dailyCoffee(
        1,
        (d) => 80 - 4.0 * d.amount,
        amountOf: (random, _) => 1 + random.nextInt(2),
      );
      final HabitInsight slope = judged(doseFollows, input);
      final HabitInsight line = judged(doseLineFollows, input);
      expect(line.cut, 2);
      expect(pValueOf(line), isNotNull);
      expect(pValueOf(line), closeTo(pValueOf(slope)!, 1e-9));
    });

    test('is discounted for every place it was looked for', () {
      final InsightsInput input = dailyCoffee(
        2,
        (d) => 80.0 - (d.amount >= 3 ? 20 : 0),
      );
      // One cut on the grid: the middle of 2, 3 and 4.
      final HabitFinding once =
          judged(doseLineFollows, input, gates: const InsightGates(maxCuts: 1))
              as HabitFinding;
      final HabitFinding searched =
          judged(doseLineFollows, input) as HabitFinding;
      expect(once.cut, 3);
      expect(searched.cut, 3);
      expect(searched.effect, closeTo(once.effect, 1e-9));
      expect(searched.pValue / once.pValue, closeTo(3, 1e-6));
      expect(searched.interval.low, lessThan(once.interval.low));
      expect(searched.interval.high, greaterThan(once.interval.high));
    });

    test('on noise, the best-looking of the cuts is rarely a finding', () {
      int amount = 0, time = 0;
      for (int seed = 0; seed < 100; seed++) {
        final InsightsInput input = dailyCoffee(seed, (_) => 80);
        if (judged(doseLineFollows, input) is HabitFinding) amount++;
        if (judged(lastUseLineFollows, input) is HabitFinding) time++;
      }
      // 5 in 100 is the most a single comparison is allowed.
      expect(amount, lessThanOrEqualTo(10));
      expect(time, lessThanOrEqualTo(10));
    });

    test('on sleep, carries the part at the same bedtime, at the same '
        'line', () {
      final InsightsInput input = dailyCoffee(
        4,
        (d) => 80.0 - (d.amount >= 3 ? 20 : 0),
      );
      final Random random = Random(4);
      final HabitInsight line = judged(
        doseLineFollows,
        InsightsInput(
          uses: input.uses,
          outcomes: <DailyOutcome>[
            ...input.outcomes,
            // Asleep between 23:00 and midnight whatever the amount, in
            // minutes after noon.
            for (int i = 0; i < days; i++)
              DailyOutcome(
                date: addDays(start, i + 1),
                metricId: sleepOnsetId,
                value: 11 * 60.0 + random.nextInt(60),
              ),
          ],
          from: input.from,
          through: input.through,
        ),
      );
      final HabitInsight? part = (line as HabitFinding).sameBedtime;
      expect(part, isA<HabitFinding>());
      expect(part!.kind, InsightKind.doseLine);
      expect(part.cut, line.cut);
      expect(part.cut, 3);
      expect((part as HabitFinding).effect, closeTo(line.effect, 3));
    });

    test('has nowhere to go in an amount that barely varies', () {
      final HabitInsight line = judged(
        doseLineFollows,
        dailyCoffee(0, (_) => 80, amountOf: (_, i) => i % 20 == 0 ? 2 : 1),
      );
      expect((line as HabitRefusal).reason, RefusalReason.steadyAmount);
      expect(line.cut, isNull);
      expect(
        refusalReason(line, (id) => id),
        'A line in the amount: nearly the same each day, so there’s no '
        'difference to compare',
      );
    });
  });

  test('a cut-off time for the last use is found on the hour it was set', () {
    for (int seed = 0; seed < 20; seed++) {
      // 15 days in each hour from 14:00 to 21:59, so the hours tried are
      // 15:00, 17:00, 18:00, 20:00 and 21:00.
      final InsightsInput input = dailyCoffee(
        seed,
        (d) => 80.0 - (d.lastMinutes >= 18 * 60 ? 20 : 0),
        lastOf: (random, i) => (14 + i % 8) * 60 + random.nextInt(60),
      );
      final HabitInsight line = judged(lastUseLineFollows, input);
      expect(line, isA<HabitFinding>(), reason: 'seed $seed');
      line as HabitFinding;
      expect(line.kind, InsightKind.lastUseLine);
      expect(line.cut, 18 * 60);
      expect(line.exposedDays, days ~/ 2);
      expect(line.effect, inInclusiveRange(-29, -11));
    }
  });

  group('the report', () {
    test('shows the line and not the slope it also explains, and nothing of '
        'an archived habit', () {
      final InsightsInput input = dailyCoffee(
        3,
        (d) => 80.0 - (d.amount >= 3 ? 30 : 0),
      );
      final List<HabitFinding> amount = <HabitFinding>[
        for (final HabitFinding f in computeInsights(input).findings)
          if (f.kind == InsightKind.dose || f.kind == InsightKind.doseLine) f,
      ];
      expect(amount.single.kind, InsightKind.doseLine);
      expect(amount.single.cut, 3);

      final InsightsReport archived = computeInsights(
        InsightsInput(
          uses: input.uses,
          outcomes: input.outcomes,
          from: input.from,
          through: input.through,
          archived: const <String>{'Coffee'},
        ),
      );
      expect(archived.findings, isEmpty);
      expect(archived.refused, isEmpty);
    });

    test('keeps one of a slope and a line for a habit and outcome, the one '
        'less likely to be chance', () {
      final HabitFinding slope = finding(InsightKind.dose, 0, pValue: 0.001);
      final HabitFinding line = finding(InsightKind.doseLine, 3, pValue: 1e-4);
      final HabitFinding weakLine = finding(
        InsightKind.doseLine,
        3,
        pValue: 0.01,
      );
      final HabitFinding elsewhere = finding(
        InsightKind.doseLine,
        3,
        metricId: 'sleepREM',
      );
      final HabitFinding time = finding(InsightKind.lastUseLine, 900);
      expect(
        oneOfSlopeAndLine(<HabitFinding>[slope, line, elsewhere, time]),
        <HabitFinding>[line, elsewhere, time],
      );
      expect(oneOfSlopeAndLine(<HabitFinding>[slope, weakLine]), <HabitFinding>[
        slope,
      ]);
    });
  });

  test('a cut-off reads on the 24-hour clock, past midnight as such', () {
    expect(
      findingLine(finding(InsightKind.lastUseLine, 900), 'en'),
      'Last use at 15:00 or later: deep sleep 14 min less',
    );
    expect(
      findingLine(finding(InsightKind.lastUseLine, 1440), 'en'),
      'Last use at midnight or later: deep sleep 14 min less',
    );
    expect(
      findingLine(finding(InsightKind.lastUseLine, 1500), 'en'),
      'Last use at 01:00 after midnight or later: deep sleep 14 min less',
    );
  });
}
