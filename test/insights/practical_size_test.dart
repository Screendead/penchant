import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

HabitFinding finding(
  String metricId,
  double effect, {
  String habitId = 'Wine',
  InsightKind kind = InsightKind.use,
  double step = 1,
  double? spread,
}) => HabitFinding(
  habitId: habitId,
  metricId: metricId,
  lagDays: 1,
  usableDays: 90,
  exposedDays: 40,
  raw: null,
  kind: kind,
  step: step,
  effect: effect,
  interval: Interval(effect * 1.5, effect * 0.5),
  standardized: effect / 20,
  pValue: 0.001,
  spread: spread,
);

void main() {
  test('every outcome with copy has a floor and a family', () {
    for (final String id in <String>[
      'sleepInBed',
      'sleepAsleep',
      'sleepAwake',
      'sleepCore',
      'sleepDeep',
      'sleepREM',
      'heartRateVariabilitySDNN',
      'restingHeartRate',
      'respiratoryRate',
      'oxygenSaturation',
      'appleSleepingWristTemperature',
      'stepCount',
      'sleepingHeartRate',
      'heartRate',
      'activeEnergyBurned',
    ]) {
      expect(metricCopy(id), isNotNull, reason: id);
      expect(metricFloors[id], isNotNull, reason: id);
    }
  });

  test('the interquartile range interpolates between order statistics', () {
    expect(interquartileRange(<double>[1, 2, 3, 4, 5]), 2);
    expect(interquartileRange(<double>[1, 2, 3, 4]), 1.5);
    expect(interquartileRange(<double>[7]), 0);
  });

  group('the floor', () {
    test('judges a use effect as it is', () {
      expect(practicalSize(finding('sleepREM', -12)), closeTo(1.2, 1e-9));
      expect(practicalSize(finding('sleepREM', -8)), lessThan(1));
      expect(practicalSize(finding('restingHeartRate', 1.5)), 1.5);
    });

    test('judges a per-hour slope across the usual spread of last uses', () {
      // 3 min an hour later is small per unit, but last uses spread over 4 h.
      final HabitFinding wide = finding(
        'sleepCore',
        -3,
        kind: InsightKind.lastUse,
        step: 60,
        spread: 240,
      );
      expect(typicalEffect(wide), closeTo(-12, 1e-9));
      expect(practicalSize(wide), greaterThan(1));
      // 15 min an hour is large per unit, but last uses spread over 30 min.
      final HabitFinding narrow = finding(
        'sleepCore',
        -15,
        kind: InsightKind.lastUse,
        step: 60,
        spread: 30,
      );
      expect(typicalEffect(narrow), closeTo(-7.5, 1e-9));
      expect(practicalSize(narrow), lessThan(1));
    });

    test('judges a dose across the usual spread of day totals', () {
      expect(
        practicalSize(
          finding('stepCount', -400, kind: InsightKind.dose, spread: 3),
        ),
        closeTo(1.2, 1e-9),
      );
      expect(
        practicalSize(
          finding('stepCount', -400, kind: InsightKind.dose, spread: 2),
        ),
        lessThan(1),
      );
    });
  });

  test('the report drops a clear but small difference to the refusals', () {
    // Tea every other day shortens core sleep by 4 min, with 1 min of noise:
    // far inside the statistics, far under the 10 min floor.
    final Random random = Random(1);
    final DateTime start = DateTime(2026, 1, 1);
    final List<HabitUse> uses = <HabitUse>[];
    final List<DailyOutcome> outcomes = <DailyOutcome>[];
    for (int i = 0; i < 120; i++) {
      final DateTime day = addDays(start, i);
      final bool tea = i.isEven;
      if (tea) {
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
          metricId: 'sleepCore',
          value: 200 - (tea ? 4 : 0) + random.nextDouble() * 2 - 1,
        ),
      );
    }
    final InsightsReport report = computeInsights(
      InsightsInput(
        uses: uses,
        outcomes: outcomes,
        from: start,
        through: addDays(start, 120),
      ),
    );
    expect(report.findings, isEmpty);
    final HabitRefusal refused = report.refused.single;
    expect(refused.reason, RefusalReason.tooSmall);
    expect(refused.effect, closeTo(-4, 0.5));
    expect(
      refusalReason(refused, (id) => id),
      'Too small to matter: under 10 min a night of core sleep',
    );
  });

  test('a habit whose only finding is too small is refused, saying so', () {
    final HabitRefusal tooSmall = HabitRefusal(
      habitId: 'Tea',
      metricId: 'sleepCore',
      lagDays: 1,
      usableDays: 90,
      exposedDays: 90,
      raw: null,
      kind: InsightKind.use,
      reason: RefusalReason.tooSmall,
      effect: -3,
      interval: const Interval(-5, -1),
      pValue: 0.001,
    );
    expect(
      refusalReason(tooSmall, (id) => id),
      'Too small to matter: under 10 min a night of core sleep',
    );
    expect(
      refusalReason(
        HabitRefusal(
          habitId: 'Tea',
          metricId: 'stepCount',
          lagDays: 1,
          usableDays: 90,
          exposedDays: 90,
          raw: null,
          kind: InsightKind.lastUse,
          step: 60,
          reason: RefusalReason.tooSmall,
        ),
        (id) => id,
      ),
      'Time of last use: too small to matter: under 1,000 a day of step '
      'count across your usual range',
    );
  });

  group('cards', () {
    test('merge one habit’s use, dose and timing findings and its sleep '
        'stages into one card, led by the largest against its floor', () {
      final List<InsightCard> cards = insightCards(<HabitFinding>[
        finding('sleepREM', -14),
        finding('sleepCore', -12),
        finding('sleepAsleep', -25),
        finding('sleepREM', -4, kind: InsightKind.dose, spread: 2.75),
        finding(
          'sleepAsleep',
          -11,
          kind: InsightKind.lastUse,
          step: 60,
          spread: 120,
        ),
        finding('restingHeartRate', 2),
        finding('sleepDeep', -15, habitId: 'Tea'),
      ]);
      expect(cards.map((c) => (c.habitId, c.family)), <(String, MetricFamily)>[
        // 25 min over a 10 min floor.
        ('Wine', MetricFamily.sleep),
        // 2 bpm over 1.
        ('Wine', MetricFamily.heart),
        ('Tea', MetricFamily.sleep),
      ]);
      final InsightCard sleep = cards.first;
      expect(sleep.headline.metricId, 'sleepAsleep');
      expect(sleep.headline.kind, InsightKind.use);
      expect(
        sleep.others.map((f) => (f.metricId, f.kind)),
        <(String, InsightKind)>[
          ('sleepAsleep', InsightKind.lastUse),
          ('sleepREM', InsightKind.use),
          ('sleepCore', InsightKind.use),
          ('sleepREM', InsightKind.dose),
        ],
      );
    });

    test('word their secondary lines by kind', () {
      expect(
        findingLine(
          finding('sleepREM', -4, kind: InsightKind.dose, spread: 3),
          'en',
          unit: Unit.drink,
        ),
        'More per extra drink: REM sleep 4 min less',
      );
      expect(
        findingLine(
          finding(
            'sleepAsleep',
            -11,
            kind: InsightKind.lastUse,
            step: 60,
            spread: 120,
          ),
          'en',
        ),
        'Later last use: time asleep 11 min less per hour',
      );
      expect(
        findingLine(finding('sleepCore', -12), 'en'),
        'On nights after it: core sleep 12 min less',
      );
      expect(
        findingLine(finding('restingHeartRate', 2), 'en'),
        'On days after it: resting heart rate 2.0 bpm higher',
      );
    });
  });
}
