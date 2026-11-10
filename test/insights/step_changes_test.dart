import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);

double gaussian(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

Map<DateTime, double> series(
  int days,
  double Function(int i) level, {
  int seed = 1,
  double sd = 1,
}) {
  final Random r = Random(seed);
  return <DateTime, double>{
    for (int i = 0; i < days; i++)
      addDays(start, i): level(i) + sd * gaussian(r),
  };
}

void main() {
  group('levelShifts', () {
    test('finds a planted shift within a few days of where it is', () {
      final LevelShifts found = levelShifts(
        series(120, (i) => i < 50 ? 60 : 62),
      );

      final LevelShift shift = found.shifts.single;
      expect(daysBetween(addDays(start, 50), shift.at).abs(), lessThan(4));
      expect(shift.change, closeTo(2, 0.6));
      expect(shift.before, closeTo(60, 0.5));
      expect(shift.after, closeTo(62, 0.5));
      expect(shift.daysBefore + shift.daysAfter, 120);
      expect(shift.pValue, lessThan(0.001));
      expect(found.pValue, shift.pValue);
    });

    test('finds none in noise, and still gives the search its p-value', () {
      int found = 0;
      for (int seed = 0; seed < 40; seed++) {
        final LevelShifts result = levelShifts(
          series(120, (_) => 60, seed: seed),
        );
        expect(result.pValue, isNotNull);
        found += result.shifts.length;
      }
      expect(found, lessThanOrEqualTo(4));
    });

    test('a steady drift is not a shift', () {
      final LevelShifts found = levelShifts(series(120, (i) => 60 + i / 20));

      expect(found.shifts, isEmpty);
      expect(found.pValue, 1);
    });

    test('a series too short to hold a level each side is not searched', () {
      final LevelShifts found = levelShifts(
        series(2 * minShiftSideDays - 1, (i) => i < 13 ? 0 : 10),
      );

      expect(found.shifts, isEmpty);
      expect(found.pValue, isNull);
    });

    test('a week at another level is not a lasting shift', () {
      final LevelShifts found = levelShifts(
        series(120, (i) => i >= 60 && i < 67 ? 62 : 60, sd: 0.5),
      );

      expect(found.shifts, isEmpty);
    });

    test('finds two shifts, each between its neighbours\' levels', () {
      final LevelShifts found = levelShifts(
        series(180, (i) => i < 60 ? 0 : (i < 120 ? 3 : 0)),
      );

      expect(found.shifts, hasLength(2));
      expect(found.shifts.first.change, closeTo(3, 0.6));
      expect(found.shifts.last.change, closeTo(-3, 0.6));
      expect(found.shifts.first.at.isBefore(found.shifts.last.at), isTrue);
    });

    test('a constant series has nothing to find', () {
      expect(levelShifts(series(60, (_) => 5, sd: 0)).shifts, isEmpty);
    });
  });

  group('the habit models hold a shift fixed', () {
    // Coffee daily, 1 or 2 a day before day 50 and 3 or 4 after; the outcome
    // steps 1 sd at day 50 and owes nothing to the amount.
    int findings(double step) {
      int found = 0;
      for (int seed = 0; seed < 30; seed++) {
        final Random r = Random(seed);
        final List<HabitUse> uses = <HabitUse>[];
        final List<DailyOutcome> outcomes = <DailyOutcome>[];
        for (int i = 0; i < 120; i++) {
          final DateTime day = addDays(start, i);
          final int amount = (i < 50 ? 1 : 3) + r.nextInt(2);
          for (int k = 0; k < amount; k++) {
            uses.add(
              HabitUse(
                habitId: 'coffee',
                at: day.add(Duration(hours: 9 + k)),
                amount: 1,
              ),
            );
          }
          outcomes.add(
            DailyOutcome(
              date: addDays(day, 1),
              metricId: 'outcome',
              value: (i < 50 ? 0 : step) + gaussian(r),
            ),
          );
        }
        final HabitInsight result = doseFollows(
          habits: DailyHabitSeries.fromUses(uses),
          outcomes: OutcomeSeries.fromOutcomes(outcomes),
          metricId: 'outcome',
        ).single;
        if (result is HabitFinding) found++;
      }
      return found;
    }

    test('an amount that rose when the outcome stepped is not credited', () {
      expect(findings(1), lessThanOrEqualTo(3));
    });
  });

  group('measureShifts', () {
    List<DailyOutcome> resting(double Function(int i) level, {int days = 120}) {
      final Map<DateTime, double> values = series(days, level);
      return <DailyOutcome>[
        for (final MapEntry<DateTime, double> e in values.entries)
          DailyOutcome(
            date: e.key,
            metricId: 'restingHeartRate',
            value: e.value,
          ),
      ];
    }

    List<HabitUse> uses(String habit, int Function(int i) amount) => <HabitUse>[
      for (int i = 0; i < 120; i++)
        for (int k = 0; k < amount(i); k++)
          HabitUse(
            habitId: habit,
            at: addDays(start, i).add(Duration(hours: 9 + k)),
            amount: 1,
          ),
    ];

    test('names the habit whose amount changed with the shift, and no '
        'other', () {
      final result = measureShifts(
        outcomes: OutcomeSeries.fromOutcomes(resting((i) => i < 60 ? 58 : 62)),
        habits: DailyHabitSeries.fromUses(<HabitUse>[
          ...uses('coffee', (i) => i < 59 ? 1 : 3),
          ...uses('tea', (i) => 2),
          ...uses('wine', (i) => i < 59 ? 0 : 2),
        ]),
        through: addDays(start, 119),
        skip: const <String>{'wine'},
      );

      final MeasureShift shift = result.shifts.single;
      expect(shift.metricId, 'restingHeartRate');
      expect(result.searched, isEmpty);
      final HabitChange coffee = shift.habits.single;
      expect(coffee.habitId, 'coffee');
      expect(coffee.before, closeTo(1, 0.2));
      expect(coffee.after, closeTo(3, 0.2));
    });

    test('a measure with no shift adds its search to the family, and a '
        'measure the page does not name adds nothing', () {
      final result = measureShifts(
        outcomes: OutcomeSeries.fromOutcomes(<DailyOutcome>[
          ...resting((_) => 58),
          for (int i = 0; i < 120; i++)
            DailyOutcome(
              date: addDays(start, i),
              metricId: 'unnamed',
              value: i < 60 ? 0 : 10,
            ),
        ]),
        habits: DailyHabitSeries.fromUses(uses('coffee', (_) => 1)),
        through: addDays(start, 119),
      );

      expect(result.shifts, isEmpty);
      expect(result.searched, hasLength(1));
    });

    MeasureShift shiftOf(double change, double p) => MeasureShift(
      metricId: 'restingHeartRate',
      shift: LevelShift(
        at: DateTime(2026, 3, 12),
        before: 58,
        after: 58 + change,
        daysBefore: 43,
        daysAfter: 60,
        pValue: p,
      ),
    );

    test('a shift under the measure\'s floor, or lost among the other '
        'comparisons, is not found', () {
      final List<MeasureShift> judged = judgeMeasureShifts(<MeasureShift>[
        shiftOf(6, 0.0001),
        shiftOf(2, 0.0001),
      ], q: 0.1);
      expect(judged.first.found, isTrue);
      expect(judged.last.found, isFalse);

      final List<MeasureShift> crowded = judgeMeasureShifts(
        <MeasureShift>[shiftOf(6, 0.04)],
        alongside: List<double>.filled(50, 0.5),
        q: 0.1,
      );
      expect(crowded.single.found, isFalse);
    });

    test('says it in plain words', () {
      final MeasureShift shift = MeasureShift(
        metricId: 'restingHeartRate',
        shift: shiftOf(6, 0.0001).shift,
        habits: const <HabitChange>[
          HabitChange(habitId: 'coffee', before: 1.5, after: 3.46),
        ],
      );

      expect(
        measureShiftText(shift, '12 March 2026', (_) => 'Coffee', 'en'),
        <String>[
          'From 12 March 2026, your resting heart rate averaged 6.0 bpm higher '
              'than before.',
          '58.0 bpm over the 43 days before, 64.0 bpm over the 60 days from '
              'then',
          'Coffee changed around then too, from 1.5 a day to 3.5, so the two '
              'can’t be told apart.',
        ],
      );
      expect(
        measureShiftSentence(
          MeasureShift(
            metricId: 'sleepAsleep',
            shift: LevelShift(
              at: DateTime(2026, 3, 12),
              before: 430,
              after: 400,
              daysBefore: 40,
              daysAfter: 40,
              pValue: 0.001,
            ),
          ),
          '12 March 2026',
          'en',
        ),
        'From 12 March 2026, your time asleep averaged 30 min less than '
        'before.',
      );
    });
  });
}
