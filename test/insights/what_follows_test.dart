import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/what_follows.dart';

import '../fakes.dart';

const String sleep = 'sleepMinutes';
final DateTime start = DateTime(2026, 1, 5);

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// [days] days of a journal, the habits on each day chosen by [usedOn], and a
// next-night outcome of 420 + [trend] per day + [effectOf] the day's habits +
// noise (sd [noise]).
({DailyHabitSeries habits, OutcomeSeries outcomes}) journal({
  required int seed,
  int days = 120,
  required Set<String> Function(Random random, int day) usedOn,
  double Function(Set<String> used) effectOf = _noEffect,
  double trend = 0,
  double noise = 20,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final Set<String> used = usedOn(random, i);
    for (final String habit in used) {
      uses.add(
        HabitUse(
          habitId: habit,
          at: day.add(const Duration(hours: 15)),
          amount: 1,
        ),
      );
    }
    outcomes.add(
      DailyOutcome(
        date: addDays(day, 1),
        metricId: sleep,
        value: 420 + trend * i + effectOf(used) + noise * gaussian(random),
      ),
    );
  }
  return (
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
  );
}

double _noEffect(Set<String> used) => 0;

Set<String> independent(Random random, int day) => <String>{
  if (random.nextBool()) 'Coffee',
  if (random.nextBool()) 'Tea',
};

HabitInsight forHabit(List<HabitInsight> results, String id) =>
    results.singleWhere((r) => r.habitId == id);

void main() {
  test('an injected effect is found, the other habit is not credited', () {
    final data = journal(
      seed: 1,
      usedOn: independent,
      effectOf: (used) => used.contains('Coffee') ? -30 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    final HabitInsight coffee = forHabit(results, 'Coffee');
    expect(coffee, isA<HabitFinding>());
    coffee as HabitFinding;
    expect(coffee.interval.high, lessThan(0));
    expect(coffee.interval.low, lessThan(-30));
    expect(coffee.interval.high, greaterThan(-30));
    expect(coffee.standardized, lessThan(-0.5));
    expect(
      coffee.usableDays,
      daysFrom(
        data.habits.firstUse('Coffee')!,
        data.habits.lastUse('Coffee')!,
      ).length,
    );
    expect(coffee.raw!.difference, lessThan(0));

    expect(forHabit(results, 'Tea'), isA<HabitRefusal>());
    expect(
      (forHabit(results, 'Tea') as HabitRefusal).reason,
      RefusalReason.withinNoise,
    );
  });

  test('pure noise is refused', () {
    final data = journal(seed: 2, usedOn: independent);
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    expect(results.whereType<HabitFinding>(), isEmpty);
    expect(
      results.whereType<HabitRefusal>().map((r) => r.reason),
      everyElement(anyOf(RefusalReason.withinNoise, RefusalReason.tooFewDays)),
    );
  });

  test(
    'over many noise journals, about 5% of results clear a 95% interval',
    () {
      int reported = 0, tested = 0;
      for (int seed = 100; seed < 300; seed++) {
        final data = journal(seed: seed, days: 60, usedOn: independent);
        for (final HabitInsight r in whatFollows(
          habits: data.habits,
          outcomes: data.outcomes,
          metricId: sleep,
        )) {
          tested++;
          if (r is HabitFinding) reported++;
        }
      }

      expect(tested, 400);
      expect(reported / tested, lessThan(0.09));
    },
  );

  test('two co-used habits are separated', () {
    // Coffee comes with Tea three times in four, so Coffee's raw comparison
    // carries Tea's effect.
    Set<String> together(Random random, int day) {
      final bool tea = random.nextBool();
      final bool coffee = random.nextDouble() < (tea ? 0.75 : 0.25);
      return <String>{if (tea) 'Tea', if (coffee) 'Coffee'};
    }

    final data = journal(
      seed: 3,
      usedOn: together,
      effectOf: (used) => used.contains('Tea') ? -30 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    final HabitInsight coffee = forHabit(results, 'Coffee');
    expect(coffee.raw!.interval.high, lessThan(0));
    expect(coffee, isA<HabitRefusal>());
    expect((coffee as HabitRefusal).reason, RefusalReason.withinNoise);

    final HabitInsight tea = forHabit(results, 'Tea');
    expect(tea, isA<HabitFinding>());
    expect((tea as HabitFinding).interval.high, lessThan(0));
  });

  test('habits always used together are refused as entangled', () {
    final data = journal(
      seed: 4,
      usedOn: (random, day) =>
          random.nextBool() ? <String>{'Tea', 'Coffee'} : <String>{},
      effectOf: (used) => used.contains('Tea') ? -30 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    final HabitRefusal tea = forHabit(results, 'Tea') as HabitRefusal;
    final HabitRefusal coffee = forHabit(results, 'Coffee') as HabitRefusal;
    expect(tea.reason, RefusalReason.entangled);
    expect(tea.entangledWith, 'Coffee');
    expect(coffee.reason, RefusalReason.entangled);
    expect(coffee.entangledWith, 'Tea');
  });

  test('habits used together on most days are refused as entangled', () {
    // Coffee joins Tea on 95% of Tea's days and appears alone on 5% of the
    // rest: correlated near 0.9, a variance inflation above 5.
    final data = journal(
      seed: 5,
      usedOn: (random, day) {
        final bool tea = random.nextBool();
        final bool coffee = random.nextDouble() < (tea ? 0.95 : 0.05);
        return <String>{if (tea) 'Tea', if (coffee) 'Coffee'};
      },
      effectOf: (used) => used.contains('Tea') ? -30 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    for (final String id in <String>['Tea', 'Coffee']) {
      final HabitRefusal r = forHabit(results, id) as HabitRefusal;
      expect(r.reason, RefusalReason.entangled);
      expect(r.entangledWith, id == 'Tea' ? 'Coffee' : 'Tea');
    }
  });

  test('below the minimum sample everything is refused', () {
    final data = journal(
      seed: 6,
      days: 20,
      usedOn: independent,
      effectOf: (used) => used.contains('Coffee') ? -200 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    expect(
      results.map((r) => (r as HabitRefusal).reason),
      everyElement(RefusalReason.tooFewDays),
    );
  });

  test('a habit with too few days without it is refused', () {
    final data = journal(
      seed: 7,
      days: 60,
      usedOn: (random, day) => <String>{
        if (random.nextDouble() < 0.95) 'Coffee',
        if (random.nextBool()) 'Tea',
      },
    );
    final HabitRefusal coffee =
        forHabit(
              whatFollows(
                habits: data.habits,
                outcomes: data.outcomes,
                metricId: sleep,
              ),
              'Coffee',
            )
            as HabitRefusal;

    expect(coffee.reason, RefusalReason.tooFewDays);
  });

  test(
    'days with no outcome and days outside the habit\'s span are left out',
    () {
      final List<HabitUse> uses = <HabitUse>[
        for (int i = 0; i < 30; i++)
          if (i.isEven)
            HabitUse(habitId: 'Tea', at: addDays(start, i), amount: 1),
        HabitUse(habitId: 'Coffee', at: addDays(start, 29), amount: 1),
      ];
      final List<DailyOutcome> outcomes = <DailyOutcome>[
        for (int i = -10; i < 31; i++)
          if (i != 5)
            DailyOutcome(
              date: addDays(start, i),
              metricId: sleep,
              value: i.toDouble(),
            ),
      ];
      final HabitInsight tea = forHabit(
        whatFollows(
          habits: DailyHabitSeries.fromUses(uses),
          outcomes: OutcomeSeries.fromOutcomes(outcomes),
          metricId: sleep,
        ),
        'Tea',
      );

      // Tea's days 0 to 28, less day 4 (its next day, 5, has no outcome); Coffee's
      // day 29 is after Tea's last use.
      expect(tea.usableDays, 28);
    },
  );

  test('a habit with too few days with it is refused', () {
    final data = journal(
      seed: 8,
      usedOn: (random, day) => <String>{
        if (<int>{0, 25, 50, 75, 119}.contains(day)) 'Coffee',
        if (random.nextBool()) 'Tea',
      },
      effectOf: (used) => used.contains('Coffee') ? -200 : 0,
    );
    final HabitRefusal coffee =
        forHabit(
              whatFollows(
                habits: data.habits,
                outcomes: data.outcomes,
                metricId: sleep,
              ),
              'Coffee',
            )
            as HabitRefusal;

    expect(coffee.usableDays, 120);
    expect(coffee.raw!.exposedDays, 5);
    expect(coffee.reason, RefusalReason.tooFewDays);
  });

  test('a habit started or dropped mid-journal is judged on its own span', () {
    // The outcome drifts up 0.3 a day and no habit has any effect. Coded "not
    // used" before it started, Coffee's indicator would track the drift.
    int reported = 0;
    for (int seed = 0; seed < 50; seed++) {
      final data = journal(
        seed: seed,
        trend: 0.3,
        usedOn: (random, day) => <String>{
          if (random.nextBool() && day >= 60) 'Coffee',
          if (random.nextBool() && day < 70) 'Tea',
        },
      );
      final List<HabitInsight> results = whatFollows(
        habits: data.habits,
        outcomes: data.outcomes,
        metricId: sleep,
      );
      expect(forHabit(results, 'Coffee').usableDays, lessThanOrEqualTo(60));
      expect(forHabit(results, 'Tea').usableDays, lessThanOrEqualTo(70));
      if (seed == 0) {
        expect(forHabit(results, 'Coffee'), isA<HabitRefusal>());
      }
      reported += results.whereType<HabitFinding>().length;
    }

    expect(reported / 100, lessThan(0.09));
  });

  test('habits below the sample gates stay out of the model', () {
    // 24 one-off habits would fill a 30-day design and leave Coffee entangled
    // with one of them.
    final data = journal(
      seed: 9,
      days: 30,
      noise: 10,
      usedOn: (random, day) => <String>{
        if (day.isEven) 'Coffee',
        if (day < 24) 'Water$day',
      },
      effectOf: (used) => used.contains('Coffee') ? -60 : 0,
    );
    final List<HabitInsight> results = whatFollows(
      habits: data.habits,
      outcomes: data.outcomes,
      metricId: sleep,
    );

    expect(forHabit(results, 'Coffee'), isA<HabitFinding>());
    for (final HabitInsight r in results.where((r) => r.habitId != 'Coffee')) {
      expect((r as HabitRefusal).reason, RefusalReason.tooFewDays);
      expect(r.entangledWith, isNull);
    }
  });

  test('zero-amount entries are no use and move no first or last day', () {
    final DailyHabitSeries series = DailyHabitSeries.fromUses(<HabitUse>[
      HabitUse(habitId: 'Water', at: DateTime(2026, 2, 1), amount: 0),
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 1), amount: 0),
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 2), amount: 1),
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 9), amount: 0),
    ]);

    expect(series.habitIds, containsAll(<String>['Water', 'Tea']));
    expect(series.firstUse('Water'), isNull);
    expect(series.firstUse('Tea'), DateTime(2026, 3, 2));
    expect(series.lastUse('Tea'), DateTime(2026, 3, 2));
    expect(series.firstDay, DateTime(2026, 3, 2));
    expect(series.lastDay, DateTime(2026, 3, 2));
    expect(series.total('Tea', DateTime(2026, 3, 1)), 0);

    final HabitInsight water = forHabit(
      whatFollows(
        habits: series,
        outcomes: OutcomeSeries.fromOutcomes(const <DailyOutcome>[]),
        metricId: sleep,
      ),
      'Water',
    );
    expect(water.usableDays, 0);
    expect((water as HabitRefusal).reason, RefusalReason.tooFewDays);
  });

  test('uses are summed per local calendar day', () {
    final DailyHabitSeries series = DailyHabitSeries.fromUses(<HabitUse>[
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 1, 23, 30), amount: 1),
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 2, 0, 30), amount: 2),
      HabitUse(habitId: 'Tea', at: DateTime(2026, 3, 2, 22), amount: 0.5),
    ]);

    expect(series.total('Tea', DateTime(2026, 3, 1)), 1);
    expect(series.total('Tea', DateTime(2026, 3, 2, 12)), 2.5);
    expect(series.total('Coffee', DateTime(2026, 3, 2)), 0);
    expect(series.firstDay, DateTime(2026, 3, 1));
    expect(series.lastDay, DateTime(2026, 3, 2));
  });

  test('journal entries become uses by their local time and measure', () {
    final DateTime at = DateTime(2026, 3, 1, 8, 15);
    final List<HabitUse> uses = habitUsesFrom(<ViceActivity>[
      fakeActivity('Coffee', 2, at),
      fakeActivity('Tea', 1, at, amount: 0.5),
    ]).toList();

    expect(uses.map((u) => u.habitId), <String>['Coffee', 'Tea']);
    expect(uses.first.at, at);
    expect(uses.map((u) => u.amount), <num>[2, 0.5]);
  });
}
