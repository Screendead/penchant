import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';

import '../fakes.dart';

const String mood = 'moodValence';
final DateTime start = DateTime(2026, 1, 5);
final RegExp digit = RegExp(r'\d');

DailyOutcome outcome(int day, double value, [String metric = mood]) =>
    DailyOutcome(date: addDays(start, day), metricId: metric, value: value);

double gaussian(Random random) =>
    sqrt(-2 * log(1 - random.nextDouble())) * cos(2 * pi * random.nextDouble());

// One habit on a fair coin's days, and a mood log on about half of days,
// valence 0.1 give or take [spread], [shift] spreads lower on the day after
// the habit. Days without a log are absent, as Health gives them.
InsightsInput moodInput(
  int seed, {
  double shift = 0,
  double spread = 0.25,
  double logRate = 0.5,
}) {
  final Random random = Random(seed);
  const int days = 150;
  final List<HabitUse> uses = <HabitUse>[];
  final List<DailyOutcome> outcomes = <DailyOutcome>[];
  for (int i = 0; i < days; i++) {
    final DateTime day = addDays(start, i);
    final bool used = random.nextDouble() < 0.5;
    if (used) {
      uses.add(
        HabitUse(
          habitId: 'habit1',
          at: day.add(const Duration(hours: 20)),
          amount: 1,
        ),
      );
    }
    final double value =
        0.1 + spread * gaussian(random) - (used ? shift * spread : 0);
    if (random.nextDouble() < logRate) {
      outcomes.add(
        DailyOutcome(
          date: addDays(day, 1),
          metricId: mood,
          value: value.clamp(-1, 1),
        ),
      );
    }
  }
  final DateTime through = addDays(start, days);
  return InsightsInput(
    uses: uses,
    outcomes: withEnoughMood(outcomes),
    from: start,
    through: through,
  );
}

void main() {
  group('withEnoughMood', () {
    List<DailyOutcome> logs(int n) => <DailyOutcome>[
      for (int i = 0; i < n; i++) outcome(2 * i, i.isEven ? 0.2 : -0.1),
    ];

    test('leaves mood out under 14 days with a log, and keeps the rest', () {
      final List<DailyOutcome> few = <DailyOutcome>[
        ...logs(minMoodDays - 1),
        outcome(3, 4000, 'stepCount'),
      ];
      final List<DailyOutcome> got = withEnoughMood(few);
      expect(got.where((o) => o.metricId == mood), isEmpty);
      expect(got.where((o) => o.metricId == 'stepCount'), hasLength(1));
    });

    test('keeps mood from 14 days with a log', () {
      expect(withEnoughMood(logs(minMoodDays)), hasLength(minMoodDays));
    });

    test('leaves out a mood that never moves', () {
      expect(
        withEnoughMood(<DailyOutcome>[
          for (int i = 0; i < 20; i++) outcome(i, 0.3),
        ]),
        isEmpty,
      );
    });

    test('InsightsInput.from applies it', () {
      final DateTime today = DateTime(2026, 6, 1);
      InsightsInput from(int n) => InsightsInput.from(
        activities: [fakeActivity('habit1', 1, DateTime(2026, 5, 1, 9))],
        health: <hs.DailyOutcome>[
          for (int i = 0; i < n; i++)
            hs.DailyOutcome(
              addDays(DateTime(2026, 4, 1), i * 2),
              mood,
              i.isEven ? 0.4 : -0.2,
            ),
        ],
        today: today,
      );
      expect(from(minMoodDays - 1).outcomes, isEmpty);
      expect(from(minMoodDays).outcomes, hasLength(minMoodDays));
    });
  });

  group('the mood floor', () {
    test('is half the SD of daily valence, from days with no next-door day '
        'among them', () {
      final List<double> values = <double>[
        for (int i = 0; i < 20; i++) i.isEven ? 0.5 : -0.3,
      ];
      final OutcomeSeries series = OutcomeSeries.fromOutcomes(<DailyOutcome>[
        for (int i = 0; i < values.length; i++) outcome(3 * i, values[i]),
      ]);
      final double mean = values.reduce((a, b) => a + b) / values.length;
      final double sd = sqrt(
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            (values.length - 1),
      );
      expect(resolveFloors(series)[mood], closeTo(sd / 2, 1e-9));
    });

    test('is habit-blind: the same days give the same floor whatever the '
        'habit did', () {
      final InsightsInput a = moodInput(1);
      expect(
        computeInsights(
          InsightsInput(
            uses: const <HabitUse>[],
            outcomes: a.outcomes,
            from: a.from,
            through: a.through,
          ),
        ).floors[mood],
        computeInsights(a).floors[mood],
      );
    });

    test(
      'a mood difference of a whole SD is found; one of 0.2 SD seldom is, and never under the floor',
      () {
        int found = 0;
        for (int seed = 0; seed < 20; seed++) {
          final InsightsReport report = computeInsights(
            moodInput(seed, shift: 1),
          );
          final HabitFinding? use = report.findings
              .where((f) => f.metricId == mood && f.kind == InsightKind.use)
              .firstOrNull;
          if (use != null && use.effect < 0) found++;
        }
        expect(found, greaterThanOrEqualTo(16));
        int small = 0;
        for (int seed = 0; seed < 20; seed++) {
          final InsightsReport report = computeInsights(
            moodInput(seed, shift: 0.2),
          );
          final Iterable<HabitFinding> got = report.findings.where(
            (f) => f.metricId == mood,
          );
          for (final HabitFinding f in got) {
            expect(
              typicalEffect(f).abs(),
              greaterThanOrEqualTo(report.floors[mood]!),
              reason: 'seed $seed',
            );
          }
          if (got.isNotEmpty) small++;
        }
        expect(small, lessThanOrEqualTo(2));
      },
    );

    test('on noise, mood rarely yields a finding', () {
      int found = 0;
      for (int seed = 0; seed < 40; seed++) {
        final InsightsReport report = computeInsights(moodInput(seed));
        if (report.findings.any((f) => f.metricId == mood) ||
            report.shifts.any((s) => s.metricId == mood && s.found)) {
          found++;
        }
      }
      expect(found, lessThanOrEqualTo(2));
    });
  });

  group('mood copy', () {
    test('says pleasant or unpleasant, never a number', () {
      final InsightsReport report = computeInsights(moodInput(3, shift: 1));
      final HabitFinding use = report.findings.firstWhere(
        (f) => f.metricId == mood && f.kind == InsightKind.use,
      );
      final InsightCard card = insightCards(
        report.findings,
        floors: report.floors,
      ).firstWhere((c) => c.headline.metricId == mood);
      expect(card.family, MetricFamily.mood);
      final String sentence = findingSentence(use, 'Wine', 'en');
      expect(sentence, startsWith('On days after Wine, your mood averages '));
      expect(sentence, endsWith(' less pleasant.'));
      for (final String text in <String>[
        sentence,
        findingLine(use, 'en'),
        findingChange(use, 'en'),
        findingRange(use, 'en'),
      ]) {
        expect(text, isNot(contains(digit)), reason: text);
        expect(text, contains('pleasant'), reason: text);
      }
      expect(
        refusalReason(
          const HabitRefusal(
            habitId: 'habit1',
            metricId: mood,
            lagDays: 1,
            usableDays: 80,
            exposedDays: 40,
            raw: null,
            reason: RefusalReason.tooSmall,
          ),
          (_) => 'Wine',
          floors: const <String, double>{mood: 0.137},
        ),
        'Too small to matter: under half your usual day-to-day swing in mood',
      );
    });

    test('a shift reads in Health\'s own labels', () {
      final MeasureShift shift = MeasureShift(
        metricId: mood,
        shift: LevelShift(
          at: DateTime(2026, 3, 1),
          before: 0.35,
          after: -0.05,
          daysBefore: 40,
          daysAfter: 60,
          pValue: 0.001,
        ),
      );
      expect(
        measureShiftSentence(shift, '1 March 2026', 'en'),
        'From 1 March 2026, your mood averaged noticeably less pleasant than '
        'before.',
      );
      expect(
        measureShiftBasis(shift, 'en'),
        'slightly pleasant over the 40 days before, neutral over the 60 days '
        'from then',
      );
    });

    test('size and level words follow Health\'s seven labels', () {
      final MetricCopy copy = metricCopy(mood)!;
      expect(measureAmount(0.1, copy, 0, 'en'), 'slightly');
      expect(measureAmount(-0.3, copy, 0, 'en'), 'noticeably');
      expect(measureAmount(0.5, copy, 0, 'en'), 'much');
      expect(measureLevel(-1, copy, 0, 'en'), 'very unpleasant');
      expect(measureLevel(-0.5, copy, 0, 'en'), 'unpleasant');
      expect(measureLevel(0, copy, 0, 'en'), 'neutral');
      expect(measureLevel(0.6, copy, 0, 'en'), 'pleasant');
      expect(measureLevel(1, copy, 0, 'en'), 'very pleasant');
    });
  });

  test('mood carries a floor, a family, copy and a source line', () {
    expect(hs.HealthMetric.values.map((m) => m.id), contains(mood));
    expect(hs.sessionMetricIds, isNot(contains(mood)));
    expect(metricFloors[mood]!.rule, FloorRule.ownSpread);
    expect(metricFloors[mood]!.family, MetricFamily.mood);
    expect(metricEvidence(mood), contains('Norman 2003'));
  });
}
