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
      expect(practicalSize(finding('restingHeartRate', 7.5)), 1.5);
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
          finding('stepCount', -200, kind: InsightKind.dose, spread: 3),
        ),
        closeTo(1.2, 1e-9),
      );
      expect(
        practicalSize(
          finding('stepCount', -200, kind: InsightKind.dose, spread: 2),
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
      'Time of last use: too small to matter, under 500 a day of step '
      'count across your usual range',
    );
  });

  group('floors per person', () {
    final DateTime start = DateTime(2026, 1, 1);
    OutcomeSeries series(String metricId, List<double?> values) =>
        OutcomeSeries.fromOutcomes(<DailyOutcome>[
          for (int i = 0; i < values.length; i++)
            if (values[i] case final double v)
              DailyOutcome(
                date: addDays(start, i),
                metricId: metricId,
                value: v,
              ),
        ]);
    OutcomeSeries merged(List<OutcomeSeries> parts) =>
        OutcomeSeries.fromOutcomes(<DailyOutcome>[
          for (final OutcomeSeries part in parts)
            for (final String id in part.metricIds)
              for (final MapEntry<DateTime, double> day
                  in part.days(id).entries)
                DailyOutcome(date: day.key, metricId: id, value: day.value),
        ]);

    test('REM’s is 5% of the usual night asleep, 10 min with under 14 '
        'nights', () {
      final Map<String, double> floors = resolveFloors(
        series('sleepAsleep', <double>[for (int i = 0; i < 30; i++) 440]),
      );
      expect(floors['sleepREM'], closeTo(22, 1e-9));
      expect(resolveFloors(series('sleepCore', <double>[200]))['sleepREM'], 10);
      expect(
        resolveFloors(
          series('sleepAsleep', <double>[for (int i = 0; i < 13; i++) 440]),
        )['sleepREM'],
        10,
      );
    });

    test(
      'a floor inside half the night-to-night variation is raised to it',
      () {
        // Core sleep alternating 180 and 220: each change is 40, so the typical
        // error is 40 / √2 and half of it about 14 min, over the 10 min floor.
        final List<double> core = <double>[
          for (int i = 0; i < 30; i++) i.isEven ? 180 : 220,
        ];
        final Map<String, double> floors = resolveFloors(
          series('sleepCore', core),
        );
        final double error = typicalError(
          series('sleepCore', core).days('sleepCore'),
        )!;
        expect(error, closeTo(40 / sqrt2, 1));
        expect(floors['sleepCore'], closeTo(noiseShare * error, 1e-9));
        expect(floors['sleepCore'], greaterThan(10));
        // Time asleep with the same scatter keeps its larger 21 min floor.
        expect(resolveFloors(series('sleepAsleep', core))['sleepAsleep'], 21);
      },
    );

    test('the variation needs 14 pairs of next-door days', () {
      final List<double> scattered = <double>[
        for (int i = 0; i < 14; i++) i.isEven ? 100 : 200,
      ];
      // 14 days are 13 pairs.
      expect(
        typicalError(series('sleepCore', scattered).days('sleepCore')),
        isNull,
      );
      expect(resolveFloors(series('sleepCore', scattered))['sleepCore'], 10);
      // Every other night missing: no next-door pairs at all.
      expect(
        typicalError(
          series('sleepCore', <double?>[
            for (int i = 0; i < 60; i++) i.isEven ? 100.0 + i : null,
          ]).days('sleepCore'),
        ),
        isNull,
      );
    });

    test('HRV’s is half its own variation, 3 ms without enough nights', () {
      final List<double> hrv = <double>[
        for (int i = 0; i < 30; i++) i.isEven ? 40 : 42,
      ];
      final Map<String, double> floors = resolveFloors(
        merged(<OutcomeSeries>[
          series('heartRateVariabilitySDNN', hrv),
          series('restingHeartRate', <double>[for (int i = 0; i < 30; i++) 60]),
        ]),
      );
      // Under the 3 ms fallback, since the person's own swing is the floor.
      expect(
        floors['heartRateVariabilitySDNN'],
        closeTo(0.5 * 2 / sqrt2, 0.05),
      );
      expect(floors['restingHeartRate'], 5);
      expect(
        resolveFloors(
          series('heartRateVariabilitySDNN', <double>[40, 42]),
        )['heartRateVariabilitySDNN'],
        3,
      );
    });

    test('the report carries them, and a refusal names the person’s floor', () {
      final InsightsReport report = computeInsights(
        InsightsInput(
          uses: const <HabitUse>[],
          outcomes: <DailyOutcome>[
            for (int i = 0; i < 30; i++)
              DailyOutcome(
                date: addDays(start, i),
                metricId: 'sleepAsleep',
                value: 428,
              ),
          ],
          from: start,
          through: addDays(start, 30),
        ),
      );
      expect(report.floors['sleepREM'], closeTo(21.4, 1e-9));
      expect(
        refusalReason(
          HabitRefusal(
            habitId: 'Tea',
            metricId: 'sleepREM',
            lagDays: 1,
            usableDays: 90,
            exposedDays: 40,
            raw: null,
            kind: InsightKind.use,
            reason: RefusalReason.tooSmall,
          ),
          (id) => id,
          floors: report.floors,
        ),
        'Too small to matter: under 21 min a night of REM sleep',
      );
      // Judged against the person's floor, not the 10 min fallback.
      expect(
        practicalSize(finding('sleepREM', -15), floors: report.floors),
        lessThan(1),
      );
      expect(practicalSize(finding('sleepREM', -15)), greaterThan(1));
    });
  });

  test('a card says what its floor’s size has been shown to do, with the '
      'source, but not for a kept floor or an hours-after finding', () {
    expect(
      findingEvidence(finding('stepCount', 900)),
      contains('(Banach 2023)'),
    );
    expect(findingEvidence(finding('sleepAsleep', -30)), contains('21 min'));
    expect(findingEvidence(finding('sleepCore', -30)), isNull);
    expect(
      findingEvidence(
        finding('heartRateVariabilitySDNN', -8, kind: InsightKind.hoursAfter),
      ),
      isNull,
    );
    for (final String id in metricFloors.keys) {
      final String? line = metricEvidence(id);
      if (line != null) expect(line, matches(RegExp(r'\(\D+ \d{4}\)\.$')));
    }
  });

  group('cards', () {
    test('merge one habit’s use, dose and timing findings and its sleep '
        'stages into one card, led by the largest against its floor', () {
      final List<InsightCard> cards = insightCards(<HabitFinding>[
        finding('sleepREM', -14),
        finding('sleepCore', -12),
        finding('sleepAsleep', -50),
        finding('sleepREM', -4, kind: InsightKind.dose, spread: 2.75),
        finding(
          'sleepAsleep',
          -11,
          kind: InsightKind.lastUse,
          step: 60,
          spread: 240,
        ),
        finding('restingHeartRate', 9),
        finding('sleepDeep', -15, habitId: 'Tea'),
      ]);
      expect(cards.map((c) => (c.habitId, c.family)), <(String, MetricFamily)>[
        // 50 min over a 21 min floor.
        ('Wine', MetricFamily.sleep),
        // 9 bpm over 5.
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
