import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
const int days = 120;
final String deep = HealthMetric.sleepDeep.id;

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// A day's uses of one habit: [amount] split over up to three entries, the
// last at [lastMinutes] after midnight (past 24:00 runs into the next day).
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

typedef Day = ({int index, DateTime day, int amount, int lastMinutes});

// Coffee every day of [days], 1 to 4 a day, the last between 12:00 and 01:00;
// the next night's deep sleep is [value] of that day plus noise of sd 10.
InsightsInput dailyCoffee(
  int seed,
  double Function(Day d) value, {
  int Function(Random random, int index)? amountOf,
  int Function(Random random)? lastOf,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final int amount = amountOf?.call(random, i) ?? 1 + random.nextInt(4);
    final int last = lastOf?.call(random) ?? 12 * 60 + random.nextInt(13 * 60);
    uses.addAll(dayOfUse('Coffee', day, amount, last));
    outcomes.add(
      DailyOutcome(
        date: addDays(day, 1),
        metricId: deep,
        value:
            value((index: i, day: day, amount: amount, lastMinutes: last)) +
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

final List<String> metricIds = <String>[
  for (final HealthMetric m in <HealthMetric>[
    HealthMetric.sleepAsleep,
    HealthMetric.sleepCore,
    HealthMetric.sleepDeep,
    HealthMetric.sleepREM,
    HealthMetric.heartRateVariabilitySDNN,
    HealthMetric.restingHeartRate,
    HealthMetric.respiratoryRate,
    HealthMetric.stepCount,
    HealthMetric.activeEnergyBurned,
  ])
    m.id,
];

// Coffee and Tea on a fair coin's days, Water every day, each 1 to 4 a day
// with the last between 12:00 and 01:00, and nine outcomes of noise alone.
InsightsInput noise(int seed) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
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
    for (final String metric in metricIds) {
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: metric,
          value: 100 + 20 * gaussian(random),
        ),
      );
    }
  }
  return InsightsInput(
    uses: uses,
    outcomes: outcomes,
    from: start,
    through: addDays(start, days),
  );
}

List<HabitInsight> everyComparison(InsightsInput input) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  return <HabitInsight>[
    for (final String metric in metricIds) ...<HabitInsight>[
      ...whatFollows(habits: habits, outcomes: outcomes, metricId: metric),
      ...doseFollows(habits: habits, outcomes: outcomes, metricId: metric),
      ...lastUseFollows(habits: habits, outcomes: outcomes, metricId: metric),
    ],
  ];
}

double? pValueOf(HabitInsight insight) => switch (insight) {
  HabitFinding(:final double pValue) => pValue,
  HabitRefusal(:final double? pValue) => pValue,
};

void main() {
  test('on pure noise, the larger family still keeps false findings rare '
      'after the correction', () {
    const int seeds = 200;
    int checks = 0, raw = 0, rawReports = 0, after = 0, reports = 0;
    final Map<InsightKind, int> tested = <InsightKind, int>{};
    for (int seed = 0; seed < seeds; seed++) {
      final InsightsInput input = noise(seed);
      final List<HabitInsight> all = everyComparison(input);
      for (final HabitInsight i in all) {
        if (pValueOf(i) != null) {
          checks++;
          tested[i.kind] = (tested[i.kind] ?? 0) + 1;
        }
      }
      final int found = all.whereType<HabitFinding>().length;
      raw += found;
      if (found > 0) rawReports++;
      final int kept = controlFalseDiscoveries(
        all,
      ).whereType<HabitFinding>().length;
      if (seed < 10) {
        expect(
          computeInsights(input).findings.length,
          controlFalseDiscoveries(all)
              .whereType<HabitFinding>()
              .where((f) => practicalSize(f) >= 1)
              .length,
        );
      }
      after += kept;
      if (kept > 0) reports++;
    }
    // ignore: avoid_print
    print(
      'MEASURE tested=$tested checks=$checks raw=$raw rawReports=$rawReports '
      'after=$after reports=$reports',
    );
    // 2 x 9 days-with-and-without (Water has no days without), 3 x 9 each of
    // amount and time.
    expect(checks, seeds * (18 + 27 + 27));
    expect(raw / checks, inInclusiveRange(0.03, 0.07));
    expect(after / checks, lessThan(0.005));
    expect(reports / seeds, lessThan(0.15));
  });

  group('the time of the last use', () {
    test('a use before 05:00 is the previous day’s late use', () {
      final DailyHabitSeries s = DailyHabitSeries.fromUses(<HabitUse>[
        HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 1, 21, 15), amount: 1),
        HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 2, 1, 30), amount: 2),
        HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 2, 5), amount: 1),
      ]);
      expect(lateUseCutoffHour, 5);
      expect(s.lastUseMinutes('Tea', DateTime(2026, 3, 1)), 25 * 60 + 30);
      expect(s.lateDayTotal('Tea', DateTime(2026, 3, 1)), 3);
      expect(s.lastUseMinutes('Tea', DateTime(2026, 3, 2)), 5 * 60);
      // Day totals stay on the calendar day.
      expect(s.total('Tea', DateTime(2026, 3, 1)), 1);
      expect(s.total('Tea', DateTime(2026, 3, 2)), 3);
    });
  });

  test('a dose effect on a habit used every day is found, per unit', () {
    for (int seed = 0; seed < 30; seed++) {
      final InsightsReport report = computeInsights(
        // Large enough per drink to clear the 10 min floor at the narrowest
        // spread of 1 to 4 drinks.
        dailyCoffee(seed, (d) => 80 - 15.0 * d.amount),
      );
      final HabitFinding dose = report.findings.singleWhere(
        (f) => f.habitId == 'Coffee' && f.kind == InsightKind.dose,
      );
      expect(dose.step, 1);
      expect(dose.effect, inInclusiveRange(-18, -12));
      expect(dose.interval.high, lessThan(0));
      expect(dose.usableDays, greaterThan(days - 10));
      expect(report.refused.where((r) => r.habitId == 'Coffee'), isEmpty);
      expect(
        report.findings.where((f) => f.kind == InsightKind.use),
        isEmpty,
        reason: 'no days without it, so no days-with-and-without finding',
      );
    }
  });

  test('a timing effect is found, per hour, a use past midnight counting as '
      'a late one', () {
    for (int seed = 0; seed < 30; seed++) {
      final InsightsReport report = computeInsights(
        dailyCoffee(seed, (d) => 80 - 4.0 * d.lastMinutes / 60),
      );
      final HabitFinding late = report.findings.singleWhere(
        (f) => f.habitId == 'Coffee' && f.kind == InsightKind.lastUse,
      );
      expect(late.step, 60);
      expect(late.effect, inInclusiveRange(-6, -2));
      expect(late.interval.high, lessThan(0));
    }
  });

  test('an entry after midnight adds to the evening before it, for the '
      'amount as for the time', () {
    const int seeds = 30;
    double sum = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final InsightsInput input = dailyCoffee(
        seed,
        (d) => 80 - 6.0 * d.amount,
        // Every day ends between 23:00 and 02:00, so most split at midnight.
        lastOf: (random) => 23 * 60 + random.nextInt(3 * 60),
      );
      final HabitFinding dose =
          doseFollows(
                habits: DailyHabitSeries.fromUses(input.uses),
                outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
                metricId: deep,
              ).single
              as HabitFinding;
      sum += dose.effect;
    }
    // Summed per calendar day, half of each split day's amount lands on the
    // wrong night and the mean shrinks towards zero.
    expect(sum / seeds, inInclusiveRange(-7, -5));
  });

  test('a habit taken once or twice a day reads per whole unit', () {
    final InsightsInput input = dailyCoffee(
      1,
      (d) => 80 - 20.0 * d.amount,
      amountOf: (random, i) => i % 8 == 0 ? 2 : 1,
      lastOf: (random) => 9 * 60,
    );
    final HabitFinding dose =
        doseFollows(
              habits: DailyHabitSeries.fromUses(input.uses),
              outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
              metricId: deep,
            ).single
            as HabitFinding;
    expect(dose.step, 1);
    expect(dose.effect, inInclusiveRange(-30, -10));
    expect(
      findingSentence(dose, 'Coffee', 'en', unit: Unit.drink),
      startsWith('On days with one more drink logged for Coffee, your'),
    );
  });

  test('a last use that comes later by as much as the amount grows is '
      'refused as following the amount, naming no other habit', () {
    for (int seed = 0; seed < 20; seed++) {
      final Random random = Random(seed);
      final List<HabitUse> uses = <HabitUse>[];
      final List<DailyOutcome> outcomes = <DailyOutcome>[];
      for (int i = 0; i < days; i++) {
        final DateTime day = addDays(start, i);
        // From 18:00, 90 minutes apart, so the last use is set by the count.
        final int n = 1 + random.nextInt(4);
        for (int k = 0; k < n; k++) {
          uses.add(
            HabitUse(
              habitId: 'Beer',
              at: day.add(Duration(minutes: 18 * 60 + 90 * k)),
              amount: 1,
            ),
          );
        }
        if (random.nextBool()) {
          uses.add(
            HabitUse(
              habitId: 'Tea',
              at: day.add(const Duration(hours: 9)),
              amount: 1,
            ),
          );
        }
        outcomes.add(
          DailyOutcome(
            date: addDays(day, 1),
            metricId: deep,
            value: 60 + 10 * gaussian(random),
          ),
        );
      }
      final InsightsInput input = InsightsInput(
        uses: uses,
        outcomes: outcomes,
        from: start,
        through: addDays(start, days),
      );
      final HabitRefusal time =
          lastUseFollows(
                habits: DailyHabitSeries.fromUses(input.uses),
                outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
                metricId: deep,
              ).singleWhere((r) => r.habitId == 'Beer')
              as HabitRefusal;
      expect(time.reason, RefusalReason.followsAmount);
      expect(time.entangledWith, isNull);
      expect(
        refusalReason(time, (id) => id),
        'Time of last use: later on days with more, so it can’t be told '
        'apart from the amount',
      );
      for (final HabitRefusal shown in computeInsights(
        input,
      ).refused.where((r) => r.habitId == 'Beer')) {
        expect(refusalReason(shown, (id) => id), isNot(contains('Tea')));
      }
    }
  });

  test('an amount or time effect that rests on one day is refused', () {
    int doseFound = 0, timeFound = 0;
    const int seeds = 100;
    for (int seed = 0; seed < seeds; seed++) {
      final int odd = 30 + seed % 60;
      for (final bool timing in <bool>[false, true]) {
        final InsightsInput input = dailyCoffee(
          seed,
          // One day far from the rest, with a night 3 sd off after it.
          (d) => d.index == odd ? 90 : 60,
          amountOf: (random, i) =>
              !timing && i == odd ? 12 : 1 + random.nextInt(4),
          lastOf: (random) => 18 * 60 + random.nextInt(4 * 60),
        );
        final List<HabitUse> uses = timing
            ? <HabitUse>[
                for (final HabitUse u in input.uses)
                  if (startOfDay(u.at) != addDays(start, odd)) u,
                HabitUse(
                  habitId: 'Coffee',
                  at: addDays(start, odd).add(const Duration(hours: 6)),
                  amount: 1,
                ),
              ]
            : input.uses;
        final Judge judge = timing ? lastUseFollows : doseFollows;
        final HabitInsight r = judge(
          habits: DailyHabitSeries.fromUses(uses),
          outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
          metricId: deep,
        ).single;
        if (r is HabitFinding) timing ? timeFound++ : doseFound++;
      }
    }
    // Without the check, about 40% (amount) and 50% (time) were findings.
    expect(doseFound / seeds, lessThan(0.15));
    expect(timeFound / seeds, lessThan(0.15));
  });

  test('an amount that rises with the months while the outcome steps with '
      'them is not a finding', () {
    const int seeds = 200;
    int found = 0;
    double r = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final InsightsInput input = dailyCoffee(
        seed,
        (d) => 60 + 15.0 * (d.day.month - 1),
        amountOf: (random, i) => addDays(start, i).month + random.nextInt(3),
      );
      final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
      final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
      final HabitInsight dose = doseFollows(
        habits: habits,
        outcomes: outcomes,
        metricId: deep,
      ).single;
      if (dose is HabitFinding) found++;
      final List<DateTime> ds = <DateTime>[
        for (int i = 0; i < days - 1; i++) addDays(start, i),
      ];
      r += stats.correlation(
        <double>[for (final DateTime d in ds) habits.total('Coffee', d)],
        <double>[
          for (final DateTime d in ds) outcomes.value(deep, addDays(d, 1))!,
        ],
      );
    }
    // The confound is real: amount and outcome move together across months.
    expect(r / seeds, greaterThan(0.5));
    // Only the 95% level's chance findings are left.
    expect(found / seeds, lessThan(0.1));
  });

  test('an amount that barely varies is refused, with a plain reason; the '
      'page shows the reason that says more', () {
    final InsightsInput input = dailyCoffee(
      0,
      (_) => 60,
      amountOf: (random, i) => i % 20 == 0 ? 2 : 1,
      // Before midnight, so no day's total takes in the next one's.
      lastOf: (random) => 18 * 60 + random.nextInt(5 * 60),
    );
    final HabitInsight dose = doseFollows(
      habits: DailyHabitSeries.fromUses(input.uses),
      outcomes: OutcomeSeries.fromOutcomes(input.outcomes),
      metricId: deep,
    ).single;
    expect((dose as HabitRefusal).reason, RefusalReason.steadyAmount);
    expect(
      refusalReason(dose, (id) => id),
      'Amount: nearly the same each day, so there’s no difference to compare',
    );
    // Its time of last use varies, so that comparison was made and says more.
    final HabitRefusal shown = computeInsights(input).refused.single;
    expect(shown.kind, InsightKind.lastUse);
    expect(
      refusalReason(shown, (id) => id),
      'Time of last use: within the noise, no clear difference',
    );
  });

  test('a habit with nothing found shows the days-with-and-without reason '
      'over an amount’s on a tie', () {
    HabitRefusal r(InsightKind kind, int usable) => HabitRefusal(
      habitId: 'Tea',
      metricId: deep,
      lagDays: 1,
      usableDays: usable,
      exposedDays: 5,
      raw: null,
      kind: kind,
      reason: RefusalReason.tooFewDays,
    );
    expect(
      refusalReason(r(InsightKind.dose, 5), (id) => id),
      'Amount: too few days with it yet: 5 of 21',
    );
    expect(
      refusalReason(r(InsightKind.lastUse, 5), (id) => id),
      'Time of last use: too few days with it yet: 5 of 21',
    );
  });

  group('copy', () {
    HabitFinding finding(InsightKind kind, double step) => HabitFinding(
      habitId: 'Coffee',
      metricId: deep,
      lagDays: 1,
      usableDays: 120,
      exposedDays: 120,
      raw: null,
      kind: kind,
      step: step,
      effect: -6.2,
      interval: const stats.Interval(-9.1, -3.3),
      standardized: -0.5,
      pValue: 0.001,
    );

    test('an amount reads per unit', () {
      final HabitFinding f = finding(InsightKind.dose, 1);
      expect(
        findingSentence(f, 'Coffee', 'en', unit: Unit.drink),
        'On days with one more drink logged for Coffee, your deep sleep that '
        'night averages 6 min less.',
      );
      expect(findingRange(f, 'en'), 'Range: 3 to 9 min less');
      expect(findingBasis(f, 'Coffee'), 'From 120 days with Coffee');
    });

    test('a wide amount reads per its step, and times as uses', () {
      expect(
        findingSentence(
          finding(InsightKind.dose, 10),
          'Run',
          'en',
          unit: Unit.minute,
        ),
        'On days with 10 more minutes logged for Run, your deep sleep that '
        'night averages 6 min less.',
      );
      expect(
        findingSentence(
          finding(InsightKind.dose, 1),
          'Tea',
          'en',
          unit: Unit.time,
        ),
        startsWith('On days with one more use logged for Tea, your'),
      );
    });

    test('a time of last use reads per hour later', () {
      expect(
        findingSentence(finding(InsightKind.lastUse, 60), 'Coffee', 'en'),
        'On days your last use of Coffee is an hour later, your deep sleep '
        'that night averages 6 min less.',
      );
    });

    // No word agrees with the name, so a plural or uncountable one reads as
    // well as a singular one.
    for (final (String habit, Unit unit) in <(String, Unit)>[
      ('Coffee', Unit.drink),
      ('Gummies', Unit.item),
      ('Nuts', Unit.item),
      ('Water', Unit.drink),
    ]) {
      test('$habit reads in every sentence', () {
        String sentence(InsightKind kind, double step) =>
            findingSentence(finding(kind, step), habit, 'en', unit: unit);
        expect(
          sentence(InsightKind.use, 1),
          'On nights after $habit, your deep sleep averages 6 min less.',
        );
        expect(
          sentence(InsightKind.dose, 1),
          'On days with one more ${unit.singular} logged for $habit, your '
          'deep sleep that night averages 6 min less.',
        );
        expect(
          sentence(InsightKind.dose, 5),
          'On days with 5 more ${unit.plural} logged for $habit, your deep '
          'sleep that night averages 6 min less.',
        );
        expect(
          sentence(InsightKind.lastUse, 60),
          'On days your last use of $habit is an hour later, your deep sleep '
          'that night averages 6 min less.',
        );
      });
    }
  });

  test('an amount whose effect rests on one day says so, not that it is '
      'within the noise', () {
    final Random random = Random(1);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < 31; i++) {
      final DateTime day = addDays(start, i);
      final int amount = i == 15 ? 10 : 1 + random.nextInt(3);
      uses.addAll(dayOfUse('Gummies', day, amount, 20 * 60));
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: deep,
          value: 60 + (i == 15 ? 50 : 10 * gaussian(random)),
        ),
      );
    }
    final HabitInsight dose = doseFollows(
      habits: DailyHabitSeries.fromUses(uses),
      outcomes: OutcomeSeries.fromOutcomes(outcomes),
      metricId: deep,
    ).single;
    expect((dose as HabitRefusal).reason, RefusalReason.oneDay);
    expect(dose.pValue, lessThan(0.01));
    expect(
      refusalReason(dose, (id) => id),
      'Amount: rests on one unusual day, so it may not hold on the others',
    );
  });
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
