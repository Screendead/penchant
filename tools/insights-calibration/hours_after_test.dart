// Monte Carlo rates for the hours-after comparisons in
// lib/insights/hours_after.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/hours_after_test.dart
// Each line prints, per window, the share of seeds with a heart rate finding
// before the false-discovery correction.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import '../../test/insights/hours_after_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) => '${(100 * n / of).toStringAsFixed(1)}%';

void scenario(String name, Synthetic Function(int seed) make) {
  final Map<HourWindow, int> found = <HourWindow, int>{};
  int checks = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final Synthetic s = make(seed);
    for (final HabitInsight i in hoursAfter(
      plan: planHoursAfter(s.uses, s.through),
      uses: s.uses,
      samples: s.samples,
    )) {
      if (i.metricId != 'heartRate' || i.habitId != 'Coffee') continue;
      checks++;
      if (i is HabitFinding) found[i.window!] = (found[i.window!] ?? 0) + 1;
    }
  }
  stdout.writeln(
    '$name ($seeds seeds, $checks checks): '
    '${[for (final w in hoursAfterWindows) '${w.start}-${w.end} ${pct(found[w] ?? 0, seeds)}'].join(', ')}',
  );
}

double noise(Random r) => gaussian(r);

void main() {
  test('hours after a use', () {
    scenario('noise', (seed) => synthetic(seed));
    scenario('morning rise 20 bpm', (seed) => synthetic(seed, morningRise: 20));
    scenario(
      'walk after 70% of Coffee',
      (seed) => synthetic(seed, walkAfterCoffee: 0.7),
    );
    scenario(
      '+6 bpm at 60-120',
      (seed) => synthetic(
        seed,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 6 : 0,
      ),
    );
    scenario(
      '+3 bpm at 60-120',
      (seed) => synthetic(
        seed,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 3 : 0,
      ),
    );
    scenario(
      '+1 bpm at 60-120',
      (seed) => synthetic(
        seed,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 1 : 0,
      ),
    );
    scenario(
      '+1.5 bpm at 0-30, 60 days',
      (seed) => synthetic(
        seed,
        days: 60,
        effect: (h, m) => h == 'Coffee' && m < 30 ? 1.5 : 0,
      ),
    );
    scenario(
      '+3 bpm at 0-30, 60 days',
      (seed) => synthetic(
        seed,
        days: 60,
        effect: (h, m) => h == 'Coffee' && m < 30 ? 3 : 0,
      ),
    );
  });

  test('whole page on noise', () {
    const Map<String, HabitPattern> habits = <String, HabitPattern>{
      'Coffee': (chance: 0.6, from: 6 * 60, to: 11 * 60),
      'Tea': (chance: 0.5, from: 13 * 60, to: 18 * 60),
      'Water': (chance: 1, from: 8 * 60, to: 20 * 60),
    };
    const List<String> metrics = <String>[
      'sleepInBed',
      'sleepAsleep',
      'sleepAwake',
      'sleepCore',
      'sleepDeep',
      'sleepREM',
      'heartRateVariabilitySDNN',
      'restingHeartRate',
      'sleepingHeartRate',
    ];
    int hoursRaw = 0, hoursTested = 0;
    int kept = 0, hoursKept = 0, reports = 0, hoursReports = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final Synthetic s = synthetic(seed, habits: habits);
      final Random r = Random(seed + 100000);
      final List<DailyOutcome> outcomes = <DailyOutcome>[
        for (int i = 0; i <= 120; i++)
          for (final String m in metrics)
            DailyOutcome(
              date: addDays(syntheticStart, i),
              metricId: m,
              value: noise(r),
            ),
      ];
      final InsightsInput input = InsightsInput(
        uses: s.uses,
        outcomes: outcomes,
        from: syntheticStart,
        through: s.through,
        samples: s.samples,
      );
      final List<HabitInsight> hours = hoursAfter(
        plan: insightsHoursAfterPlan(input.uses, s.through),
        uses: input.uses,
        samples: input.samples,
      );
      for (final HabitInsight i in hours) {
        final bool p = switch (i) {
          HabitFinding() => true,
          HabitRefusal(:final pValue) => pValue != null,
        };
        if (p) hoursTested++;
        if (i is HabitFinding) hoursRaw++;
      }
      final InsightsReport report = computeInsights(input);
      final int h = report.findings
          .where((f) => f.kind == InsightKind.hoursAfter)
          .length;
      kept += report.findings.length;
      hoursKept += h;
      if (report.findings.isNotEmpty) reports++;
      if (h > 0) hoursReports++;
    }
    stdout.writeln(
      'whole page on noise ($seeds seeds; Coffee, Tea, Water; 9 day '
      'outcomes): hours-after checks $hoursTested, raw ${pct(hoursRaw, hoursTested)}; '
      'after BH, hours-after findings ${pct(hoursKept, hoursTested)} of its checks, '
      'reports with any finding ${pct(reports, seeds)}, with an hours-after '
      'finding ${pct(hoursReports, seeds)} ($kept findings in all)',
    );
  });
}
