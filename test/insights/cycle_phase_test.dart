import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/cycle_phase.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
const String heart = 'restingHeartRate';

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// Flow on the first [bleed] days of each [length]-day cycle from [start].
List<DateTime> flow({required int cycles, int length = 28, int bleed = 5}) =>
    <DateTime>[
      for (int c = 0; c < cycles; c++)
        for (int d = 0; d < bleed; d++) addDays(start, c * length + d),
    ];

CyclePhase? phaseOn(DayCondition phases, DateTime day) =>
    switch (phases.level(day)) {
      null => null,
      final int l => CyclePhase.values[l],
    };

// [cycles] cycles of 28 days. The habit is used on [luteal] of luteal days
// and [other] of the rest; the next day's resting heart rate is 60, 3 bpm
// higher in the luteal phase, plus [effect] after the habit, plus noise.
({DailyHabitSeries habits, OutcomeSeries outcomes, DayCondition phases})
journal({
  required int seed,
  int cycles = 7,
  double luteal = 0.7,
  double other = 0.2,
  double effect = 0,
}) {
  final DayCondition phases = cyclePhases(flow(cycles: cycles + 1));
  final Random random = Random(seed);
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < cycles * 28; i++) {
    final DateTime day = addDays(start, i);
    final bool inLuteal = phaseOn(phases, day) == CyclePhase.luteal;
    final bool used = random.nextDouble() < (inLuteal ? luteal : other);
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
    final bool nextLuteal = phaseOn(phases, next) == CyclePhase.luteal;
    outcomes.add(
      DailyOutcome(
        date: next,
        metricId: heart,
        value:
            60 + (nextLuteal ? 3 : 0) + (used ? effect : 0) + gaussian(random),
      ),
    );
  }
  return (
    habits: DailyHabitSeries.fromUses(uses),
    outcomes: OutcomeSeries.fromOutcomes(outcomes),
    phases: phases,
  );
}

void main() {
  group('cyclePhases', () {
    test('menstrual through the bleed, luteal for the 14 days before the '
        'next, follicular between', () {
      final DayCondition phases = cyclePhases(flow(cycles: 3));
      expect(phaseOn(phases, start), CyclePhase.menstrual);
      expect(phaseOn(phases, addDays(start, 4)), CyclePhase.menstrual);
      expect(phaseOn(phases, addDays(start, 5)), CyclePhase.follicular);
      expect(phaseOn(phases, addDays(start, 13)), CyclePhase.follicular);
      expect(phaseOn(phases, addDays(start, 14)), CyclePhase.luteal);
      expect(phaseOn(phases, addDays(start, 27)), CyclePhase.luteal);
      expect(phaseOn(phases, addDays(start, 28)), CyclePhase.menstrual);
    });

    test('no phase before the first period or in the cycle still open', () {
      final DayCondition phases = cyclePhases(flow(cycles: 3));
      expect(phases.level(addDays(start, -1)), isNull);
      expect(phases.level(addDays(start, 56)), isNull);
      expect(phases.level(addDays(start, 70)), isNull);
    });

    test('a day without flow inside the bleed stays menstrual', () {
      final DayCondition phases = cyclePhases(<DateTime>[
        start,
        addDays(start, 1),
        addDays(start, 3),
        addDays(start, 28),
      ]);
      expect(phaseOn(phases, addDays(start, 2)), CyclePhase.menstrual);
      expect(phaseOn(phases, addDays(start, 3)), CyclePhase.menstrual);
      expect(phaseOn(phases, addDays(start, 4)), CyclePhase.follicular);
    });

    test('a cycle too short or too long has no phases', () {
      // Spotting on day 12 splits a cycle in two short ones.
      final DayCondition spotted = cyclePhases(<DateTime>[
        start,
        addDays(start, 12),
        addDays(start, 28),
      ]);
      for (int d = 0; d < 28; d++) {
        expect(spotted.level(addDays(start, d)), isNull, reason: 'day $d');
      }
      // A missed log reads as one cycle of 56 days.
      final DayCondition missed = cyclePhases(<DateTime>[
        start,
        addDays(start, 56),
        addDays(start, 84),
      ]);
      expect(missed.level(addDays(start, 30)), isNull);
      expect(phaseOn(missed, addDays(start, 60)), CyclePhase.follicular);
    });
  });

  group('held fixed', () {
    test('a habit that only rides along with the luteal phase is found '
        'without it and not with it', () {
      final r = journal(seed: 7);
      final HabitInsight blind = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
      ).single;
      expect(blind, isA<HabitFinding>());
      expect((blind as HabitFinding).heldFixed, isEmpty);

      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[r.phases],
      ).single;
      expect(held, isA<HabitRefusal>());
      expect((held as HabitRefusal).reason, RefusalReason.withinNoise);
    });

    test('a real effect is still found, and says the phase was held', () {
      final r = journal(seed: 7, effect: 2);
      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[r.phases],
      ).single;
      expect(held, isA<HabitFinding>());
      final HabitFinding f = held as HabitFinding;
      expect(f.heldFixed, <String>{cyclePhaseId});
      expect(f.interval.low, lessThan(2));
      expect(f.interval.high, greaterThan(2));
      expect(
        findingBasis(f, 'Coffee'),
        endsWith(', compared within the same phase of your cycle'),
      );
    });

    test('too few days of a phase leaves the comparison as it was', () {
      final r = journal(seed: 7, effect: 2);
      // One whole cycle: 5 menstrual, 9 follicular and 14 luteal days, but
      // the habit's span holds every day, so menstrual has under a week.
      final DayCondition one = cyclePhases(flow(cycles: 2));
      final HabitInsight plain = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
      ).single;
      final HabitInsight held = whatFollows(
        habits: r.habits,
        outcomes: r.outcomes,
        metricId: heart,
        conditions: <DayCondition>[one],
      ).single;
      expect(held, isA<HabitFinding>());
      expect((held as HabitFinding).heldFixed, isEmpty);
      expect(held.effect, (plain as HabitFinding).effect);
      expect(findingBasis(held, 'Coffee'), isNot(contains('cycle')));
    });
  });

  test('flow days are no outcome, only the phase held fixed', () {
    final DateTime today = addDays(start, 120);
    final InsightsInput input = InsightsInput.from(
      activities: const [],
      health: <hs.DailyOutcome>[
        for (final DateTime d in flow(cycles: 4))
          hs.DailyOutcome(d, hs.HealthMetric.menstrualFlow.id, 1),
        hs.DailyOutcome(start, heart, 60),
      ],
      today: today,
    );
    expect(input.outcomes.map((DailyOutcome o) => o.metricId).toSet(), <String>{
      heart,
    });
    expect(input.conditions.single.id, cyclePhaseId);
    expect(
      phaseOn(input.conditions.single, addDays(start, 20)),
      CyclePhase.luteal,
    );
  });
}
