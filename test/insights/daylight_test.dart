import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/daylight.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/what_follows.dart';

const String heart = 'restingHeartRate';

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

void expectNear(DateTime? actual, DateTime expected) {
  expect(actual, isNotNull);
  expect(
    actual!.difference(expected).inSeconds.abs(),
    lessThanOrEqualTo(180),
    reason: '$actual against $expected',
  );
}

// [days] days from [from]: the habit used on [high] of days whose [measure]
// is above 0 and [low] of the rest; the next day's resting heart rate is 60
// plus 3 per unit of the measure, plus [effect] after the habit, plus noise.
({DailyHabitSeries habits, OutcomeSeries outcomes}) journal({
  required DateTime from,
  required int days,
  required double Function(DateTime day) measure,
  double high = 0.7,
  double low = 0.2,
  double effect = 0,
  int seed = 7,
}) {
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(from, i);
    final bool used = random.nextDouble() < (measure(day) > 0 ? high : low);
    if (used) {
      uses.add(
        HabitUse(
          habitId: 'h',
          at: day.add(const Duration(hours: 15)),
          amount: 1,
        ),
      );
    }
    final DateTime next = addDays(day, 1);
    outcomes.add(
      DailyOutcome(
        date: next,
        metricId: heart,
        value: 60 + 3 * measure(next) + (used ? effect : 0) + gaussian(random),
      ),
    );
  }
  return (
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
  );
}

void main() {
  group('sunTimes', () {
    final RoughLocation london = RoughLocation.exact(51.5, -0.13);

    test('London at midsummer', () {
      final t = sunTimes(DateTime(2024, 6, 21), london);
      // NOAA: 04:43 and 21:21 BST.
      expectNear(t.sunrise, DateTime.utc(2024, 6, 21, 3, 43));
      expectNear(t.sunset, DateTime.utc(2024, 6, 21, 20, 21));
      expect(t.hours, closeTo(16 + 38 / 60, 0.05));
    });

    test('London at midwinter', () {
      final t = sunTimes(DateTime(2024, 12, 21), london);
      // NOAA: 08:04 and 15:54 GMT.
      expectNear(t.sunrise, DateTime.utc(2024, 12, 21, 8, 4));
      expectNear(t.sunset, DateTime.utc(2024, 12, 21, 15, 54));
      expect(t.hours, closeTo(7 + 50 / 60, 0.05));
    });

    test('Sydney in its summer', () {
      final t = sunTimes(
        DateTime(2024, 12, 21),
        RoughLocation.exact(-33.87, 151.21),
      );
      // 05:41 and 20:05 AEDT.
      expectNear(t.sunrise, DateTime.utc(2024, 12, 20, 18, 41));
      expectNear(t.sunset, DateTime.utc(2024, 12, 21, 9, 5));
    });

    test('the equator at the equinox has a little over 12 hours', () {
      final t = sunTimes(DateTime(2024, 3, 20), RoughLocation(0, 0));
      expect(t.hours, closeTo(12.12, 0.05));
    });

    test('above the Arctic Circle the sun stays up, then down', () {
      final RoughLocation north = RoughLocation(70, 19);
      final summer = sunTimes(DateTime(2024, 6, 21), north);
      expect(summer.hours, 24);
      expect(summer.sunrise, isNull);
      final winter = sunTimes(DateTime(2024, 12, 21), north);
      expect(winter.hours, 0);
      expect(winter.sunset, isNull);
    });
  });

  group('rough location', () {
    test('is whole degrees', () {
      final RoughLocation at = RoughLocation(51.51, -0.13);
      expect((at.latitude, at.longitude), (52.0, 0.0));
    });

    test('a time zone gives its city; an unknown one gives nothing', () {
      expect(roughLocationOfZone('Europe/London'), RoughLocation(52, 0));
      expect(roughLocationOfZone('Australia/Sydney'), RoughLocation(-34, 151));
      expect(roughLocationOfZone('Nowhere/Else'), isNull);
      expect(roughLocationOfZone(null), isNull);
    });

    test('the place with the most time wins', () {
      final DateTime t = DateTime(2026, 3, 2, 9);
      final PlaceStore store = PlaceStore(
        places: const <Place>[
          Place(id: 1, latitude: 48.85, longitude: 2.35, visits: 3),
          Place(id: 2, latitude: 40.71, longitude: -74.01, visits: 1),
        ],
        stays: <PlaceStay>[
          PlaceStay(1, t, t.add(const Duration(hours: 1))),
          PlaceStay(2, t, t.add(const Duration(hours: 5))),
          PlaceStay(1, t, null),
        ],
      );
      expect(roughLocationOfPlaces(store), RoughLocation(41, -74));
      expect(roughLocationOfPlaces(const PlaceStore()), isNull);
    });
  });

  group('held fixed', () {
    // A quantity that swings within each month, which the month terms miss.
    double swing(DateTime day) =>
        sin(2 * pi * daysBetween(DateTime(2026), day) / 10);
    DayCondition swings(DateTime from, int days) => DayCondition.measure(
      id: dayLengthId,
      value: <DateTime, double>{
        for (int i = 0; i <= days + 1; i++)
          addDays(from, i): swing(addDays(from, i)),
      },
    );

    test('a habit that only rides along with it is found without it and '
        'not with it', () {
      final DateTime from = DateTime(2026, 1, 5);
      final r = journal(from: from, days: 150, measure: swing);
      final HabitInsight blind = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
      ).single;
      expect(blind, isA<HabitFinding>());
      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[swings(from, 150)],
      ).single;
      expect(held, isA<HabitRefusal>());
    });

    test('a real effect is still found, and says what was held', () {
      final DateTime from = DateTime(2026, 1, 5);
      final r = journal(from: from, days: 150, measure: swing, effect: 2);
      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[swings(from, 150)],
      ).single;
      expect(held, isA<HabitFinding>());
      final HabitFinding f = held as HabitFinding;
      expect(f.heldFixed, <String>{dayLengthId});
      expect(f.interval.low, lessThan(2));
      expect(f.interval.high, greaterThan(2));
      expect(
        findingBasis(f, 'Coffee'),
        endsWith(', compared at the same length of day'),
      );
    });

    test('real day length over months adds nothing the month terms miss, so '
        'the comparison is unchanged', () {
      final DateTime from = DateTime(2026, 1, 5);
      final r = journal(
        from: from,
        days: 200,
        measure: (_) => 0,
        high: 0.4,
        low: 0.4,
        effect: 2,
      );
      final HabitInsight plain = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
      ).single;
      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[
          dayLengths(
            RoughLocation(52, 0),
            from: from,
            through: addDays(from, 201),
          ),
        ],
      ).single;
      expect(held, isA<HabitFinding>());
      expect((held as HabitFinding).heldFixed, isEmpty);
      expect(held.effect, (plain as HabitFinding).effect);
    });
  });

  test('the report holds day length only with a location', () {
    final DateTime today = DateTime(2026, 3, 1);
    InsightsInput input(RoughLocation? at) => InsightsInput.from(
      activities: const [],
      health: const [],
      today: today,
      location: at,
    );
    expect(
      input(null).conditions.map((c) => c.id),
      isNot(contains(dayLengthId)),
    );
    // No entries: nothing to hold it over.
    expect(
      input(RoughLocation(52, 0)).conditions.map((c) => c.id),
      isNot(contains(dayLengthId)),
    );
  });
}
