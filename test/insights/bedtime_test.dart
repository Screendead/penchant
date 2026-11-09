import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
final String core = HealthMetric.sleepCore.id;
final String hrv = HealthMetric.heartRateVariabilitySDNN.id;

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// [days] evenings of Coffee, its one use at [last] (minutes after midnight),
// bed at [bed] given that time, waking at 07:00; core sleep is 0.55 of the
// minutes in bed plus [direct] per hour later of the use, plus noise of sd 10.
// [onset] puts the night's sleep onset in the outcomes.
({DailyHabitSeries habits, OutcomeSeries outcomes}) evenings(
  int seed, {
  int days = 200,
  required int Function(Random random) last,
  required int Function(Random random, int last, int amount) bed,
  double direct = 0,
  bool onset = true,
  int Function(Random random)? amount,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final int l = last(random);
    final int a = amount?.call(random) ?? 1;
    for (int k = 0; k < a; k++) {
      uses.add(
        HabitUse(
          habitId: 'Coffee',
          at: day.add(Duration(minutes: l - 60 * (a - 1 - k))),
          amount: 1,
        ),
      );
    }
    final int b = bed(random, l, a);
    final double inBed = (24 + 7) * 60.0 - b;
    final DateTime night = addDays(day, 1);
    outcomes
      ..add(
        DailyOutcome(
          date: night,
          metricId: core,
          value: 0.55 * inBed + direct * l / 60 + 10 * gaussian(random),
        ),
      )
      ..add(
        DailyOutcome(date: night, metricId: hrv, value: 50 + gaussian(random)),
      );
    if (onset) {
      outcomes.add(
        DailyOutcome(date: night, metricId: sleepOnsetId, value: b - 720.0),
      );
    }
  }
  return (
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
  );
}

HabitInsight timing(
  ({DailyHabitSeries habits, OutcomeSeries outcomes}) data, [
  String? metric,
]) => lastUseFollows(
  habits: data.habits,
  outcomes: data.outcomes,
  metricId: metric ?? core,
).single;

// The last use between 19:00 and 24:00.
int evening(Random random) => 19 * 60 + random.nextInt(5 * 60);

// Bed from 22:30, half an hour later for each hour later the last use, plus
// up to an hour and a half.
int halfway(Random random, int last, int _) =>
    22 * 60 + 30 + (last - 19 * 60) ~/ 2 + random.nextInt(91);

void main() {
  test('the engine names the ids Health sends', () {
    expect(HealthMetric.sleepOnset.id, sleepOnsetId);
    expect(sleepMinutesIds, <String>{
      for (final HealthMetric m in <HealthMetric>[
        HealthMetric.sleepInBed,
        HealthMetric.sleepAsleep,
        HealthMetric.sleepAwake,
        HealthMetric.sleepCore,
        HealthMetric.sleepDeep,
        HealthMetric.sleepREM,
      ])
        m.id,
    });
    expect(metricCopy(sleepOnsetId), isNull);
    expect(metricCopy(HealthMetric.sleepEnd.id), isNull);
  });

  test('a later last use that only means a later bedtime is not credited '
      'with the sleep it cuts', () {
    int last(Random r) => evening(r);
    int bedAfter(Random r, int l, int _) => l + 30;
    // Without the onset, the old reading: 0.55 of an hour less core sleep.
    final HabitInsight without = timing(
      evenings(0, last: last, bed: bedAfter, onset: false),
    );
    expect((without as HabitFinding).effect, closeTo(-33, 1));

    final HabitInsight exact = timing(evenings(0, last: last, bed: bedAfter));
    expect((exact as HabitRefusal).reason, RefusalReason.followsBedtime);
    expect(
      refusalReason(exact, (id) => id),
      'Time of last use: moves with when you fall asleep, so it can’t be '
      'told apart from your bedtime',
    );

    // Bed half an hour later for each hour later, give or take 45 minutes:
    // the two can be told apart, and holding bedtime fixed leaves nothing.
    int found = 0, foundWithout = 0;
    for (int seed = 0; seed < 40; seed++) {
      HabitInsight r(bool onset) =>
          timing(evenings(seed, last: last, bed: halfway, onset: onset));
      if (r(true) is HabitFinding) found++;
      if (r(false) is HabitFinding) foundWithout++;
    }
    expect(foundWithout, greaterThanOrEqualTo(36));
    expect(found, lessThanOrEqualTo(4));
  });

  test('a later last use with bedtime unmoved is still found', () {
    int found = 0;
    for (int seed = 0; seed < 20; seed++) {
      final HabitInsight r = timing(
        evenings(
          seed,
          last: evening,
          bed: (random, _, _) => 23 * 60 + random.nextInt(60),
          direct: -10,
        ),
      );
      if (r is HabitFinding) {
        found++;
        expect(r.effect, closeTo(-10, 4));
      }
    }
    expect(found, greaterThanOrEqualTo(18));
  });

  test('a direct effect is found beside the bedtime it also moves', () {
    final HabitInsight r = timing(
      evenings(0, last: evening, bed: halfway, direct: -10),
    );
    expect((r as HabitFinding).effect, closeTo(-10, 4));
  });

  test('an amount that only means a later bedtime is not credited either', () {
    int found = 0, foundWithout = 0;
    for (int seed = 0; seed < 40; seed++) {
      ({DailyHabitSeries habits, OutcomeSeries outcomes}) data(bool onset) =>
          evenings(
            seed,
            last: (_) => 20 * 60,
            amount: (random) => 1 + random.nextInt(4),
            // Twenty minutes later to bed for each one, give or take ten.
            bed: (random, _, amount) =>
                22 * 60 + 20 * amount + random.nextInt(21) - 10,
            onset: onset,
          );
      HabitInsight dose(bool onset) => doseFollows(
        habits: data(onset).habits,
        outcomes: data(onset).outcomes,
        metricId: core,
      ).single;
      if (dose(true) is HabitFinding) found++;
      if (dose(false) is HabitFinding) foundWithout++;
    }
    expect(foundWithout, greaterThanOrEqualTo(36));
    expect(found, lessThanOrEqualTo(4));
  });

  test('outcomes other than minutes of sleep keep their model', () {
    for (int seed = 0; seed < 5; seed++) {
      HabitInsight r(bool onset) => timing(
        evenings(seed, last: evening, bed: halfway, onset: onset),
        hrv,
      );
      final HabitInsight a = r(true), b = r(false);
      expect(a.runtimeType, b.runtimeType);
      if (a is HabitRefusal && b is HabitRefusal) {
        expect(a.reason, b.reason);
        expect(a.effect, b.effect);
      } else {
        expect((a as HabitFinding).effect, (b as HabitFinding).effect);
      }
    }
  });

  test('the night that ended today keeps its onset', () {
    final DateTime today = DateTime(2026, 3, 1, 9);
    final InsightsInput input = InsightsInput.from(
      activities: const [],
      health: <hs.DailyOutcome>[
        for (final String id in <String>[core, sleepOnsetId, hrv])
          hs.DailyOutcome(DateTime(2026, 3, 1), id, 1),
      ],
      today: today,
    );
    expect(input.outcomes.map((o) => o.metricId).toSet(), <String>{
      core,
      sleepOnsetId,
    });
  });
}
