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
// next-night outcome of 420 + [effectOf] the day's habits + noise (sd 20).
({DailyHabitSeries habits, OutcomeSeries outcomes}) journal({
  required int seed,
  int days = 120,
  required Set<String> Function(Random random) usedOn,
  double Function(Set<String> used) effectOf = _noEffect,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final Set<String> used = usedOn(random);
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
        value: 420 + effectOf(used) + 20 * gaussian(random),
      ),
    );
  }
  // Zero-amount entries on the first and last day pin the default range to
  // all [days] whatever the habits did.
  uses
    ..add(HabitUse(habitId: 'Water', at: start, amount: 0))
    ..add(HabitUse(habitId: 'Water', at: addDays(start, days - 1), amount: 0));
  return (
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
  );
}

double _noEffect(Set<String> used) => 0;

Set<String> independent(Random random) => <String>{
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
    expect(coffee.usableDays, 120);
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
        ).where((r) => r.habitId != 'Water')) {
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
    Set<String> together(Random random) {
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
      usedOn: (random) =>
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
      usedOn: (random) {
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
      usedOn: (random) => <String>{
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

  test('days with no outcome and days before the journal are left out', () {
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

    // 30 journal days, less day 4 (its next day, 5, has no outcome).
    expect(tea.usableDays, 29);
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
