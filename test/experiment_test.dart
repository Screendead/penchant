import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/experiment.dart';
import 'package:tracker/insights/experiment_copy.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

HabitFinding _finding({
  String metricId = 'sleepDeep',
  InsightKind kind = InsightKind.use,
  double effect = -14,
}) => HabitFinding(
  habitId: 'wine',
  metricId: metricId,
  lagDays: 1,
  usableDays: 212,
  exposedDays: 61,
  raw: null,
  kind: kind,
  effect: effect,
  interval: Interval(effect - 8, effect + 8),
  standardized: -0.5,
  pValue: 0.001,
);

ExperimentPlan _plan({int weeks = 6, int seed = 42}) => ExperimentPlan.start(
  _finding(),
  today: DateTime(2026, 11, 13),
  weeks: weeks,
  seed: seed,
);

// Box-Muller, from a seeded Random so the simulations repeat.
double _normal(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

Map<DateTime, double> _outcomes(
  ExperimentPlan plan,
  Random r, {
  double effect = 0,
  double spread = 16,
}) => <DateTime, double>{
  for (final ({DateTime day, bool none}) d in plan.schedule)
    addDays(d.day, plan.lagDays): 60 + spread * _normal(r) + (d.none ? effect : 0),
};

void main() {
  group('days', () {
    test('each week has 3 or 4 none days and the plan is half and half', () {
      for (int seed = 0; seed < 200; seed++) {
        for (final int weeks in experimentLengths) {
          final ExperimentPlan plan = _plan(weeks: weeks, seed: seed);
          expect(plan.noneDays, weeks * 7 ~/ 2);
          for (int w = 0; w < weeks; w++) {
            expect(
              experimentWeek(seed, w).where((bool n) => n).length,
              anyOf(3, 4),
            );
          }
        }
      }
    });

    test('a seed gives the same days, and running on keeps them', () {
      final ExperimentPlan plan = _plan(seed: 7);
      expect(
        plan.schedule.map((d) => d.none).toList(),
        _plan(seed: 7).schedule.map((d) => d.none).toList(),
      );
      final ExperimentPlan longer = plan.extended(
        experimentExtendWeeks,
        today: plan.end,
      );
      expect(longer.days, 70);
      expect(
        longer.schedule.take(42).map((d) => d.none).toList(),
        plan.schedule.map((d) => d.none).toList(),
      );
      expect(longer.weekStarts[6], addDays(plan.end, 1));
    });

    test('weekends fall on both sides across seeds', () {
      int noneWeekends = 0, usualWeekends = 0;
      for (int seed = 0; seed < 50; seed++) {
        for (final ({DateTime day, bool none}) d in _plan(seed: seed).schedule) {
          if (d.day.weekday == DateTime.saturday) {
            d.none ? noneWeekends++ : usualWeekends++;
          }
        }
      }
      expect(noneWeekends / (noneWeekends + usualWeekends), closeTo(0.5, 0.08));
    });

    test('starts tomorrow and knows its days', () {
      final ExperimentPlan plan = _plan();
      expect(plan.start, DateTime(2026, 11, 14));
      expect(plan.end, DateTime(2026, 12, 25));
      expect(plan.indexOf(DateTime(2026, 11, 13)), isNull);
      expect(plan.indexOf(DateTime(2026, 11, 22, 21)), 8);
      expect(plan.noneOn(DateTime(2026, 11, 13)), isNull);
    });

    test('a night measure is in by the morning after the last day', () {
      final ExperimentPlan plan = _plan();
      expect(plan.finishedBy(plan.end, night: true), isFalse);
      expect(plan.finishedBy(addDays(plan.end, 1), night: true), isTrue);
      expect(plan.finishedBy(addDays(plan.end, 1), night: false), isFalse);
    });

    test('round trips through the stored form', () {
      final ExperimentPlan plan = _plan().copyWith(notifyMinutes: () => 1050);
      final ExperimentStore store = ExperimentStore.decode(
        ExperimentStore(active: plan, finished: <ExperimentPlan>[plan]).encode(),
      );
      expect(store.active!.toJson(), plan.toJson());
      expect(store.finished.single.toJson(), plan.toJson());
      expect(ExperimentStore.decode(<int>[1, 2, 3]).active, isNull);
    });
  });

  group('which findings', () {
    test('a sleep, heart or activity day-with finding, in numbers', () {
      expect(canExperiment(_finding()), isTrue);
      expect(canExperiment(_finding(metricId: 'restingHeartRate')), isTrue);
      expect(canExperiment(_finding(metricId: 'workoutMinutes')), isTrue);
      expect(canExperiment(_finding(metricId: 'moodValence')), isFalse);
      expect(canExperiment(_finding(metricId: 'remindersMissed')), isFalse);
      expect(canExperiment(_finding(kind: InsightKind.dose)), isFalse);
    });
  });

  group('analysis', () {
    test('a missed none day stays a none day', () {
      final ExperimentPlan plan = _plan();
      final ({DateTime day, bool none}) first = plan.schedule.firstWhere(
        (d) => d.none,
      );
      final DateTime late = first.day.add(const Duration(hours: 21));
      final DateTime afterMidnight = addDays(
        first.day,
        1,
      ).add(const Duration(hours: 1));
      final Map<DateTime, double> outcomes = <DateTime, double>{
        for (final d in plan.schedule)
          addDays(d.day, 1): d.none ? 70.0 : 60.0,
      };
      final ExperimentResult r = analyseExperiment(
        plan,
        outcomes: outcomes,
        uses: <DateTime>[late, afterMidnight],
      );
      expect(r.missed, 1);
      expect(r.noneValues, 21);
      expect(r.difference, 10);
      expect(r.days[plan.indexOf(first.day)!], ExperimentDay.missed);
      // A use before 18:00 keeps the plan.
      expect(
        analyseExperiment(
          plan,
          outcomes: outcomes,
          uses: <DateTime>[first.day.add(const Duration(hours: 17))],
        ).missed,
        0,
      );
    });

    test('a night with no data is left out and counted', () {
      final ExperimentPlan plan = _plan();
      final Map<DateTime, double> outcomes = _outcomes(plan, Random(1))
        ..remove(addDays(plan.start, 1))
        ..remove(addDays(plan.start, 2));
      final ExperimentResult r = analyseExperiment(
        plan,
        outcomes: outcomes,
        uses: const <DateTime>[],
      );
      expect(r.missing, 2);
      expect(r.values, 40);
    });

    test('no effect: the range leaves out zero about 5% of the time', () {
      final Random random = Random(2026);
      const int runs = 2000;
      int clear = 0;
      for (int i = 0; i < runs; i++) {
        final ExperimentPlan plan = _plan(seed: i);
        if (analyseExperiment(
          plan,
          outcomes: _outcomes(plan, random),
          uses: const <DateTime>[],
        ).clear) {
          clear++;
        }
      }
      // 2000 runs at 5%: a standard error of about 0.5 points.
      expect(clear / runs, closeTo(0.05, 0.015));
    });

    test('a planted 14 min effect: found about 4 times in 5, centred', () {
      final Random random = Random(17);
      const int runs = 1000;
      int clear = 0, covered = 0;
      double sum = 0;
      for (int i = 0; i < runs; i++) {
        final ExperimentPlan plan = _plan(seed: i);
        final ExperimentResult r = analyseExperiment(
          plan,
          outcomes: _outcomes(plan, random, effect: 14),
          uses: const <DateTime>[],
        );
        sum += r.difference;
        if (r.clear && r.difference > 0) clear++;
        if (r.interval!.low <= 14 && r.interval!.high >= 14) covered++;
      }
      expect(sum / runs, closeTo(14, 0.5));
      expect(clear / runs, closeTo(expectedPower(14, 16, 6), 0.05));
      expect(covered / runs, closeTo(0.95, 0.02));
    });
  });

  group('expected certainty', () {
    test('matches the notes\' table for a spread of 16 min', () {
      expect(expectedHalfWidth(16, 2), closeTo(18.6, 0.2));
      expect(expectedHalfWidth(16, 4), closeTo(12.4, 0.2));
      expect(expectedHalfWidth(16, 6), closeTo(10.0, 0.2));
      expect(expectedHalfWidth(16, 8), closeTo(8.6, 0.2));
      expect(expectedPower(14, 16, 6), closeTo(0.79, 0.03));
    });

    test('Welch matches a hand-worked case', () {
      final Interval i = welchInterval(
        <double>[1, 2, 3, 4],
        <double>[2, 4, 6, 8],
      )!;
      // d = -2.5, se² = 1.667/4 + 6.667/4 = 2.083, df = 4.41, t ≈ 2.70.
      expect((i.low + i.high) / 2, closeTo(-2.5, 1e-9));
      expect((i.high - i.low) / 2, closeTo(2.70 * sqrt(2.0833), 0.1));
      expect(welchInterval(<double>[1], <double>[1, 2]), isNull);
    });

    test('spread needs two weeks of values', () {
      final DateTime today = DateTime(2026, 11, 13);
      expect(
        experimentSpread(<DateTime, double>{
          for (int i = 0; i < 13; i++) addDays(today, -i): i.toDouble(),
        }, today),
        isNull,
      );
      expect(
        experimentSpread(<DateTime, double>{
          for (int i = 0; i < 20; i++) addDays(today, -i): i.isEven ? 0 : 2,
        }, today),
        closeTo(1.026, 0.01),
      );
    });
  });

  group('notifications', () {
    test('a week ahead, never naming the habit, none when off', () {
      final ExperimentPlan plan = _plan().copyWith(
        notifyMinutes: () => 17 * 60 + 30,
      );
      final List<ExperimentNotice> notices = experimentNotices(
        plan,
        DateTime(2026, 11, 21, 18),
      );
      expect(notices, hasLength(experimentNoticesAhead));
      expect(notices.first.at, DateTime(2026, 11, 22, 17, 30));
      expect(notices.first.title, 'Experiment, day 9 of 42');
      expect(notices.first.id, experimentNoticeBase + 8);
      for (final ExperimentNotice n in notices) {
        expect('${n.title} ${n.body}', isNot(contains('wine')));
        expect(
          n.body,
          plan.noneOn(n.at)!
              ? 'Today is a none day, from 18:00.'
              : ExperimentCopy.noticeUsual,
        );
      }
      expect(experimentNotices(_plan(), DateTime(2026, 11, 21)), isEmpty);
    });
  });

  group('words', () {
    test('the result and plan lines', () {
      final ExperimentWords words = ExperimentWords('sleepDeep', 'en');
      expect(words.range(2, 22), 'Range: 2 to 22 min more');
      expect(words.range(-10, 22), 'Range: 10 min less to 22 min more');
      expect(words.range(-22, -2), 'Range: 2 to 22 min less');
      expect(words.plusMinus(9.98), '±10');
      expect(words.before(_plan()), startsWith(
        'Before the experiment your journal showed 14 min more (6 to 22).',
      ));
    });
  });
}
