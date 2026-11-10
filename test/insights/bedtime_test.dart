import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/health_source.dart' show HealthMetric;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart' as stats;
import 'package:tracker/insights/what_follows.dart';

final DateTime start = DateTime(2026, 1, 5);
final String core = HealthMetric.sleepCore.id;
final String hrv = HealthMetric.heartRateVariabilitySDNN.id;

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// [days] evenings of Coffee, its one use at [last] (minutes after midnight),
// bed at [bed] given that time, waking at 07:00; core sleep is 0.55 of the
// minutes in bed plus [direct] per hour later of the use, plus noise of sd 10;
// HRV is 50 plus [hrvPerHour] per hour later of the use, plus noise of sd 1.
// [onset] puts the night's sleep onset in the outcomes, [misread] minutes
// off on day i.
({DailyHabitSeries habits, OutcomeSeries outcomes}) evenings(
  int seed, {
  int days = 200,
  required int Function(Random random) last,
  required int Function(Random random, int last, int amount) bed,
  double direct = 0,
  double hrvPerHour = 0,
  bool onset = true,
  int Function(Random random)? amount,
  double Function(int i)? misread,
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
        DailyOutcome(
          date: night,
          metricId: hrv,
          value: 50 + hrvPerHour * l / 60 + gaussian(random),
        ),
      );
    if (onset) {
      outcomes.add(
        DailyOutcome(
          date: night,
          metricId: sleepOnsetId,
          value: b - 720.0 + (misread?.call(i) ?? 0),
        ),
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

  // The part left at the same bedtime, beside the whole effect.
  HabitInsight? part(HabitInsight total) => (total as HabitFinding).sameBedtime;

  test('a later last use that only means a later bedtime shows its whole '
      'effect, and none of it at the same bedtime', () {
    int last(Random r) => evening(r);
    int bedAfter(Random r, int l, int _) => l + 30;
    // 0.55 of the half hour less in bed for each hour later.
    final HabitInsight exact = timing(evenings(0, last: last, bed: bedAfter));
    expect((exact as HabitFinding).effect, closeTo(-33, 1));
    expect((part(exact) as HabitRefusal).reason, RefusalReason.followsBedtime);
    expect(
      bedtimeLine(exact, 'en'),
      '33 min less per hour later, which can’t be told apart from your '
      'bedtime',
    );

    // Without the onset there is no part to give.
    final HabitInsight without = timing(
      evenings(0, last: last, bed: bedAfter, onset: false),
    );
    expect((without as HabitFinding).effect, exact.effect);
    expect(without.sameBedtime, isNull);
    expect(bedtimeLine(without, 'en'), isNull);

    // Bed half an hour later for each hour later, give or take 45 minutes:
    // the two can be told apart, and at the same bedtime nothing is left.
    int found = 0, held = 0;
    for (int seed = 0; seed < 40; seed++) {
      final HabitInsight r = timing(evenings(seed, last: last, bed: halfway));
      if (r is! HabitFinding) continue;
      found++;
      if (r.sameBedtime is HabitFinding) held++;
    }
    expect(found, greaterThanOrEqualTo(36));
    expect(held, lessThanOrEqualTo(4));
  });

  test('a later last use with bedtime unmoved is found whole and at the '
      'same bedtime alike', () {
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
      if (r is HabitFinding && r.sameBedtime is HabitFinding) {
        found++;
        expect(r.effect, closeTo(-10, 4));
        expect((r.sameBedtime! as HabitFinding).effect, closeTo(-10, 4));
      }
    }
    expect(found, greaterThanOrEqualTo(18));
  });

  test('a direct effect beside the bedtime it also moves: the whole, then '
      'the part at the same bedtime', () {
    final HabitInsight r = timing(
      evenings(0, last: evening, bed: halfway, direct: -10),
    );
    // -10 direct, plus 0.55 of the half hour later to bed per hour.
    expect((r as HabitFinding).effect, closeTo(-26.5, 4));
    final HabitFinding held = part(r)! as HabitFinding;
    expect(held.effect, closeTo(-10, 4));
    expect(held.step, r.step);
    expect(
      bedtimeLine(r, 'en'),
      matches(
        RegExp(
          r'^\d+ min less per hour later, \d+ min of it at the '
          r'same bedtime$',
        ),
      ),
    );
    expect(
      findingSentence(r, 'Coffee', 'en'),
      allOf(
        startsWith(
          'On days your last use of Coffee is an hour later, your core sleep '
          'that night averages ',
        ),
        isNot(contains('bedtime')),
      ),
    );
  });

  test('an amount that only means a later bedtime shows whole, and none of '
      'it at the same bedtime', () {
    int found = 0, held = 0;
    for (int seed = 0; seed < 40; seed++) {
      final ({DailyHabitSeries habits, OutcomeSeries outcomes}) data = evenings(
        seed,
        last: (_) => 20 * 60,
        amount: (random) => 1 + random.nextInt(4),
        // Twenty minutes later to bed for each one, give or take ten.
        bed: (random, _, amount) =>
            22 * 60 + 20 * amount + random.nextInt(21) - 10,
      );
      final HabitInsight r = doseFollows(
        habits: data.habits,
        outcomes: data.outcomes,
        metricId: core,
      ).single;
      if (r is! HabitFinding) continue;
      found++;
      if (r.sameBedtime is HabitFinding) held++;
    }
    expect(found, greaterThanOrEqualTo(36));
    expect(held, lessThanOrEqualTo(4));
  });

  // One more drink, twenty minutes later to bed, give or take half an hour.
  ({DailyHabitSeries habits, OutcomeSeries outcomes}) drinks(
    int seed, {
    double Function(int i)? misread,
  }) => evenings(
    seed,
    last: (_) => 20 * 60,
    amount: (random) => 1 + random.nextInt(4),
    bed: (random, _, amount) => 22 * 60 + 20 * amount + random.nextInt(61) - 30,
    misread: misread,
  );
  HabitInsight dose(({DailyHabitSeries habits, OutcomeSeries outcomes}) d) =>
      doseFollows(
        habits: d.habits,
        outcomes: d.outcomes,
        metricId: core,
      ).single;

  test('a misread onset is left out of the part at the same bedtime, not the '
      'whole', () {
    // A sleep past noon read from the wrong night (a day early), and an
    // afternoon nap taken for the night, each on 4 of the 200 nights. Held
    // fixed, either would leave bedtime barely held and the part credited
    // with what bedtime does.
    double misread(int i) => switch (i % 50) {
      0 => -1440,
      25 => -480,
      _ => 0,
    };
    final HabitInsight r = dose(drinks(0, misread: misread));
    expect(r.usableDays, 200);
    expect(part(r)!.usableDays, 192);
    int held = 0;
    for (int seed = 0; seed < 40; seed++) {
      final HabitInsight total = dose(drinks(seed, misread: misread));
      if (total is HabitFinding && total.sameBedtime is HabitFinding) held++;
    }
    expect(held, lessThanOrEqualTo(4));
  });

  test('with a bedtime read on too few nights, the whole effect still says '
      'the part could not be told', () {
    // Only 10 of the 200 nights read an onset inside the night.
    final HabitInsight r = timing(
      evenings(
        0,
        last: evening,
        bed: (_, int l, _) => l + 30,
        misread: (int i) => i < 10 ? 0 : -1440,
      ),
    );
    expect((r as HabitFinding).effect, closeTo(-33, 1));
    expect((part(r) as HabitRefusal).reason, RefusalReason.tooFewDays);
    expect(part(r)!.usableDays, 10);
    expect(
      bedtimeLine(r, 'en'),
      endsWith(
        'per hour later, too few nights with a bedtime to tell the part at '
        'the same bedtime',
      ),
    );
  });

  test('the part at the same bedtime is per the whole effect’s step', () {
    // One use a day of 1 to 30 minutes, bed a minute later for each; the
    // longest days' onsets are misread, so those left would pick a smaller
    // step of their own.
    final Random random = Random(3);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < 200; i++) {
      final DateTime day = addDays(start, i);
      final int minutes = 1 + random.nextInt(30);
      uses.add(
        HabitUse(
          habitId: 'Run',
          at: day.add(const Duration(hours: 18)),
          amount: minutes.toDouble(),
        ),
      );
      final int bed = 23 * 60 + minutes;
      final DateTime night = addDays(day, 1);
      outcomes
        ..add(
          DailyOutcome(
            date: night,
            metricId: core,
            value: 0.55 * ((24 + 7) * 60.0 - bed) + 10 * gaussian(random),
          ),
        )
        ..add(
          DailyOutcome(
            date: night,
            metricId: sleepOnsetId,
            value: bed - 720.0 - (minutes > 15 ? 1440 : 0),
          ),
        );
    }
    final HabitInsight r = doseFollows(
      habits: DailyHabitSeries.fromUses(uses),
      outcomes: OutcomeSeries.fromOutcomes(outcomes),
      metricId: core,
    ).single;
    expect((r as HabitFinding).step, 5);
    expect(part(r)!.step, 5);
  });

  test('the card line names the whole effect, then the part at the same '
      'bedtime', () {
    HabitFinding whole(InsightKind kind, double step, HabitInsight? held) =>
        HabitFinding(
          habitId: 'coffee',
          metricId: 'sleepAsleep',
          lagDays: 1,
          usableDays: 120,
          exposedDays: 120,
          raw: null,
          kind: kind,
          step: step,
          effect: -11,
          interval: stats.Interval(-15, -7),
          standardized: -0.5,
          pValue: 0.001,
          spread: 60,
          sameBedtime: held,
        );
    HabitFinding found(double effect) => HabitFinding(
      habitId: 'coffee',
      metricId: 'sleepAsleep',
      lagDays: 1,
      usableDays: 110,
      exposedDays: 110,
      raw: null,
      kind: InsightKind.lastUse,
      step: 60,
      effect: effect,
      interval: stats.Interval(effect - 2, effect + 2),
      standardized: -0.2,
      pValue: 0.01,
    );
    HabitRefusal refused(RefusalReason reason, {double? effect}) =>
        HabitRefusal(
          habitId: 'coffee',
          metricId: 'sleepAsleep',
          lagDays: 1,
          usableDays: 110,
          exposedDays: 110,
          raw: null,
          kind: InsightKind.lastUse,
          step: 60,
          reason: reason,
          effect: effect,
        );

    final HabitFinding time = whole(InsightKind.lastUse, 60, found(-4));
    expect(
      findingSentence(time, 'Coffee', 'en'),
      'On days your last use of Coffee is an hour later, your time asleep '
      'that night averages 11 min less.',
    );
    expect(
      bedtimeLine(time, 'en'),
      '11 min less per hour later, 4 min of it at the same bedtime',
    );
    expect(
      findingLine(time, 'en'),
      'Later last use: time asleep 11 min less per hour, 4 min of it at the '
      'same bedtime',
    );
    expect(
      bedtimeLine(whole(InsightKind.lastUse, 60, found(-14)), 'en'),
      '11 min less per hour later, 14 min less at the same bedtime',
    );
    expect(
      bedtimeLine(whole(InsightKind.lastUse, 60, found(3)), 'en'),
      '11 min less per hour later, 3 min more at the same bedtime',
    );
    for (final RefusalReason reason in <RefusalReason>[
      RefusalReason.withinNoise,
      RefusalReason.oneDay,
    ]) {
      expect(
        bedtimeLine(
          whole(InsightKind.lastUse, 60, refused(reason, effect: -1)),
          'en',
        ),
        '11 min less per hour later, none of it clear at the same bedtime',
      );
    }
    expect(
      bedtimeLine(
        whole(InsightKind.dose, 1, refused(RefusalReason.followsBedtime)),
        'en',
        unit: Unit.drink,
      ),
      '11 min less per extra drink, which can’t be told apart from your '
      'bedtime',
    );
    expect(
      bedtimeLine(
        whole(InsightKind.dose, 10, found(-4)),
        'en',
        unit: Unit.minute,
      ),
      '11 min less per extra 10 minutes, 4 min of it at the same bedtime',
    );
    // A part refused before any fit still gets a line.
    expect(
      bedtimeLine(
        whole(InsightKind.lastUse, 60, refused(RefusalReason.tooFewDays)),
        'en',
      ),
      '11 min less per hour later, too few nights with a bedtime to tell the '
      'part at the same bedtime',
    );
    for (final RefusalReason reason in <RefusalReason>[
      RefusalReason.uneven,
      RefusalReason.steadyTiming,
      RefusalReason.followsAmount,
      RefusalReason.entangled,
    ]) {
      expect(
        bedtimeLine(whole(InsightKind.lastUse, 60, refused(reason)), 'en'),
        '11 min less per hour later, the part at the same bedtime can’t be '
        'told',
      );
    }
    expect(
      findingLine(
        whole(InsightKind.lastUse, 60, refused(RefusalReason.tooFewDays)),
        'en',
      ),
      'Later last use: time asleep 11 min less per hour, too few nights with '
      'a bedtime to tell the part at the same bedtime',
    );
    // Only a finding that was never checked against bedtime has no line.
    expect(bedtimeLine(whole(InsightKind.lastUse, 60, null), 'en'), isNull);
  });

  test('outcomes other than minutes of sleep keep their model', () {
    int findings = 0;
    for (int seed = 0; seed < 5; seed++) {
      HabitInsight r(bool onset) => timing(
        evenings(
          seed,
          last: evening,
          bed: halfway,
          onset: onset,
          hrvPerHour: 3,
        ),
        hrv,
      );
      final HabitInsight a = r(true), b = r(false);
      expect(a.runtimeType, b.runtimeType);
      if (a is HabitFinding) {
        findings++;
        expect(a.sameBedtime, isNull);
      }
      if (a is HabitRefusal && b is HabitRefusal) {
        expect(a.reason, b.reason);
        expect(a.effect, b.effect);
      } else {
        expect((a as HabitFinding).effect, (b as HabitFinding).effect);
      }
    }
    // The comparison has something to find, so the check on a finding runs.
    expect(findings, greaterThan(0));
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
