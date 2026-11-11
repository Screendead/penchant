import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/payoff.dart';

import 'hours_after_synthetic.dart' show syntheticStart;
import 'payoff_synthetic.dart';

List<HabitUse> steady(String habit, int from, int to, int aDay) => <HabitUse>[
  for (int i = from; i < to; i++)
    for (int k = 0; k < aDay; k++)
      HabitUse(
        habitId: habit,
        at: addDays(syntheticStart, i).add(Duration(hours: 9 + k)),
        amount: 1,
      ),
];

List<Payoff> judge(PayoffDays d, {Set<String> skip = const <String>{}}) =>
    payoff(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      metricIds: payoffMetrics,
      through: d.through,
      skip: skip,
    );

void main() {
  final DateTime through = addDays(syntheticStart, 181);

  group('a fall, from the journal alone', () {
    test('a halving is placed within a week of where it happened', () {
      final PayoffDays d = payoffDays(1);
      final HabitFall fall = findFalls(
        DailyHabitSeries.fromUses(d.uses),
        d.through,
      )['Coffee']!;
      expect(daysBetween(d.fallDay!, fall.day).abs(), lessThanOrEqualTo(7));
      expect(fall.before, closeTo(3, 0.5));
      expect(fall.since, closeTo(1.5, 0.4));
      expect(fall.stopped, isFalse);
    });

    test('a habit with no entry since reads as stopped, from the first day '
        'without one', () {
      final HabitFall fall = findFalls(
        DailyHabitSeries.fromUses(<HabitUse>[
          ...steady('Coffee', 0, 100, 2),
          ...steady('Tea', 0, 182, 1),
        ]),
        through,
      )['Coffee']!;
      expect(fall.day, addDays(syntheticStart, 100));
      expect(fall.stopped, isTrue);
      expect(fall.before, 2);
      expect(fall.sinceDays, 82);
    });

    test('steady use, a fall too recent to have stayed, and one that came '
        'back are no fall', () {
      Map<String, HabitFall> falls(List<HabitUse> uses) =>
          findFalls(DailyHabitSeries.fromUses(uses), through);
      expect(falls(payoffDays(2, fallAt: null).uses), isEmpty);
      expect(
        falls(<HabitUse>[
          ...steady('Coffee', 0, 162, 2),
          ...steady('Coffee', 162, 182, 1),
        ]),
        isEmpty,
      );
      expect(
        falls(<HabitUse>[
          ...steady('Coffee', 0, 90, 4),
          ...steady('Coffee', 90, 168, 2),
          ...steady('Coffee', 168, 182, 4),
        ]),
        isEmpty,
      );
    });

    test('a habit used every third day must have stopped for longer than '
        'one used daily', () {
      Map<String, HabitFall> falls(int stoppedAt, {double power = 1}) =>
          findFalls(
            DailyHabitSeries.fromUses(<HabitUse>[
              for (int i = 0; i < stoppedAt; i += 3)
                ...steady('Wine', i, i + 1, 1),
              ...steady('Tea', 0, 182, 1),
            ]),
            through,
            gates: PayoffGates(occasionalPower: power),
          );

      expect(falls(140), isEmpty);
      expect(falls(140, power: 0).keys, <String>['Wine']);
      expect(falls(105).keys, <String>['Wine']);
      expect(
        findFalls(
          DailyHabitSeries.fromUses(<HabitUse>[
            ...steady('Coffee', 0, 140, 1),
            ...steady('Tea', 0, 182, 1),
          ]),
          through,
        ).keys,
        <String>['Coffee'],
      );
    });

    test('a fall of under a quarter is no fall', () {
      expect(
        findFalls(
          DailyHabitSeries.fromUses(<HabitUse>[
            ...steady('Coffee', 0, 91, 5),
            ...steady('Coffee', 91, 182, 4),
          ]),
          through,
        ),
        isEmpty,
      );
    });
  });

  group('each measure since', () {
    test('a level 1.5 sd better since the fall is found, in the measure’s '
        'units and on the right side', () {
      final List<Payoff> results = judge(payoffDays(3, shift: 1.5));
      expect(results.map((p) => p.metricId), payoffMetrics);
      expect(results.every((p) => p.found), isTrue);
      final Payoff sleep = results[0], resting = results[2];
      expect(sleep.effect, closeTo(60, 30));
      expect(sleep.interval!.low, greaterThan(0));
      expect(resting.effect, closeTo(-3, 1.5));
      expect(resting.interval!.high, lessThan(0));
      expect(sleep.baselineValues, greaterThanOrEqualTo(80));
      expect(sleep.sinceValues, greaterThanOrEqualTo(80));
      expect(sleep.capped, isFalse);
    });

    test('a measure that only drifts is not credited to the fall', () {
      final List<Payoff> results = judge(payoffDays(4, drift: 4));
      expect(results.where((p) => p.found), isEmpty);
      expect(
        results.every((p) => p.pValue != null),
        isTrue,
        reason: 'fitted, so each counts in the family',
      );
    });

    test('too few days of the measure on either side is refused unfitted', () {
      final PayoffDays d = payoffDays(5, shift: 1.5);
      final DateTime fell = findFalls(
        DailyHabitSeries.fromUses(d.uses),
        d.through,
      )['Coffee']!.day;
      final List<Payoff> results = payoff(
        uses: d.uses,
        outcomes: OutcomeSeries.fromOutcomes(
          d.outcomes.where((o) => !o.date.isBefore(addDays(fell, -10))),
        ),
        metricIds: payoffMetrics,
        through: d.through,
      );
      expect(
        results.map((p) => p.refusal),
        everyElement(PayoffRefusal.tooFewDays),
      );
      expect(results.map((p) => p.pValue), everyElement(isNull));
    });

    test('two habits that fell in the same fortnight are both refused, an '
        'archived one still counting against the other', () {
      final PayoffDays coffee = payoffDays(6, shift: 1.5);
      final PayoffDays both = (
        uses: <HabitUse>[
          ...steady('Coffee', 0, 91, 4),
          ...steady('Coffee', 91, 182, 2),
          ...steady('Tea', 0, 95, 3),
          ...steady('Tea', 95, 182, 1),
        ],
        outcomes: coffee.outcomes,
        through: coffee.through,
        fallDay: coffee.fallDay,
      );
      final List<Payoff> results = judge(both);
      expect(results.map((p) => p.habitId).toSet(), <String>{'Coffee', 'Tea'});
      expect(
        results.map((p) => p.refusal),
        everyElement(PayoffRefusal.otherFall),
      );
      expect(results.map((p) => p.pValue), everyElement(isNull));
      final List<Payoff> archived = judge(both, skip: <String>{'Tea'});
      expect(archived.map((p) => p.habitId).toSet(), <String>{'Coffee'});
      expect(archived.first.otherHabitId, 'Tea');
    });

    test('only the days up to 13 weeks after the fall are read', () {
      final PayoffDays d = payoffDays(8, days: 300, fallAt: 100, shift: 1.5);
      final Payoff sleep = judge(d).first;
      expect(sleep.capped, isTrue);
      expect(sleep.sinceValues, lessThanOrEqualTo(91));
    });
  });

  group('in the report', () {
    PayoffDays d() => payoffDays(3, shift: 1.5);
    InsightsReport report({Set<String> archived = const <String>{}}) =>
        computeInsights(
          InsightsInput(
            uses: d().uses,
            outcomes: d().outcomes,
            from: syntheticStart,
            through: addDays(d().through, 1),
            archived: archived,
          ),
        );

    test('a payoff is a finding of the report', () {
      final List<Payoff> found = report().payoffs
          .where((p) => p.found)
          .toList();
      expect(found.map((p) => p.metricId), contains('sleepAsleep'));
    });

    test('an archived habit has none', () {
      expect(report(archived: <String>{'Coffee'}).payoffs, isEmpty);
    });

    test('a finding that does not stand out in the family is chance, and '
        'one under its floor too small', () {
      final Payoff found = judge(d()).first;
      expect(
        judgePayoffs(
          <Payoff>[found],
          alongside: const <double>[],
          sizeOf: (_) => 2,
        ).single.found,
        isTrue,
      );
      final Payoff weak = Payoff(
        fall: found.fall,
        metricId: found.metricId,
        baselineValues: 90,
        sinceValues: 90,
        capped: false,
        effect: found.effect,
        interval: found.interval,
        pValue: 0.04,
      );
      expect(
        judgePayoffs(
          <Payoff>[weak],
          alongside: List<double>.filled(30, 0.8),
          sizeOf: (_) => 2,
        ).single.refusal,
        PayoffRefusal.chance,
      );
      expect(
        judgePayoffs(
          <Payoff>[found],
          alongside: const <double>[],
          sizeOf: (_) => 0.5,
        ).single.refusal,
        PayoffRefusal.tooSmall,
      );
    });
  });
}
