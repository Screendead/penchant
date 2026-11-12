// Monte Carlo rates for the hours-after comparisons in
// lib/insights/hours_after.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/hours_after_test.dart
// Each line prints, per window, the share of seeds with a heart rate finding
// before the false-discovery correction, then the reasons given for too few
// days.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart'
    show HealthSample, HealthSampleMetric;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import '../../test/insights/hours_after_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) => '${(100 * n / of).toStringAsFixed(1)}%';

void scenario(
  String name,
  Synthetic Function(int seed) make, {
  int seeds = seeds,
  String habit = 'Coffee',
}) {
  final Map<HourWindow, int> found = <HourWindow, int>{};
  final Map<String, int> reasons = <String, int>{};
  int checks = 0;
  for (int seed = 0; seed < seeds; seed++) {
    final Synthetic s = make(seed);
    for (final HabitInsight i in hoursAfter(
      plan: planHoursAfter(
        s.uses,
        s.through,
        bed: s.samples[HealthSampleMetric.bed.id]!,
        wakingSteps: s.samples[wakingStepsKey] ?? const <HealthSample>[],
      ),
      uses: s.uses,
      samples: s.samples,
    )) {
      if (i.metricId != 'heartRate' || i.habitId != habit) continue;
      checks++;
      switch (i) {
        case HabitFinding():
          found[i.window!] = (found[i.window!] ?? 0) + 1;
        case HabitRefusal(reason: RefusalReason.tooFewDays):
          final String why = refusalReason(i, (id) => id);
          reasons[why] = (reasons[why] ?? 0) + 1;
        case HabitRefusal():
      }
    }
  }
  stdout.writeln(
    '$name ($seeds seeds, $checks checks): '
    '${[for (final w in hoursAfterWindows) '${w.start}-${w.end} ${pct(found[w] ?? 0, seeds)}'].join(', ')}',
  );
  reasons.forEach((why, n) => stdout.writeln('    too few days x$n: $why'));
}

// Uses tied to waking, to the clock, to how the person feels, or to bed.
int? afterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 15 + r.nextInt(45) : null;
int? anHourAfterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 60 + r.nextInt(60) : null;
int? laterAfterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 120 + r.nextInt(60) : null;
int? weekdaysAtSeven(int wake, bool weekend, List<double> w, Random r) =>
    weekend ? null : 7 * 60 + r.nextInt(30);
int? midday(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.7 ? 9 * 60 + 5 * r.nextInt(72) : null;
// The lowest point of the day's wander among 6 times from 09:00 to 15:00.
int? inASlump(int wake, bool weekend, List<double> w, Random r) {
  if (r.nextDouble() > 0.7) return null;
  int best = -1;
  for (int k = 0; k < 6; k++) {
    final int m = 9 * 60 + 5 * r.nextInt(72);
    if (best < 0 || w[m ~/ 5] < w[best ~/ 5]) best = m;
  }
  return best;
}

int? atBedtime(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.8 ? 22 * 60 + 30 : null;

Synthetic waking(
  int seed,
  UsePolicy coffee, {
  bool lieIn = true,
  int hrEvery = 5,
  double dropReading = 0,
  double missingNight = 0,
  double splitNight = 0,
  Map<String, int> frequent = const <String, int>{},
  double Function(String habit, int minutesAfter)? effect,
  int? stepLag,
}) => wakingSynthetic(
  seed,
  weekendLieIn: lieIn,
  hrEvery: hrEvery,
  dropReading: dropReading,
  missingNight: missingNight,
  splitNight: splitNight,
  habits: <String, UsePolicy>{'Coffee': coffee},
  frequent: frequent,
  effect: effect,
  stepLag: stepLag,
);

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

  test('hours after a use, whole days with sleep', () {
    const int n = 200;
    scenario(
      'Coffee 15-60 min after waking, weekend lie-in',
      (seed) => waking(seed, afterWaking),
      seeds: n,
    );
    scenario(
      'Coffee 15-60 min after waking, no lie-in',
      (seed) => waking(seed, afterWaking, lieIn: false),
      seeds: n,
    );
    scenario(
      'Coffee 2-3 h after waking, weekend lie-in',
      (seed) => waking(seed, laterAfterWaking),
      seeds: n,
    );
    scenario(
      'Coffee weekdays 07:00-07:30',
      (seed) => waking(seed, weekdaysAtSeven),
      seeds: n,
    );
    scenario(
      'Coffee in a slump (state-dependent)',
      (seed) => waking(seed, inASlump),
      seeds: n,
    );
    scenario(
      'Coffee 09:00-15:00 at random',
      (seed) => waking(seed, midday),
      seeds: n,
    );
    scenario(
      'at random, heart rate every 10 min, 30% missing',
      (seed) => waking(seed, midday, hrEvery: 10, dropReading: 0.3),
      seeds: n,
    );
    scenario(
      'at random, 30% of nights missing, 30% split',
      (seed) => waking(seed, midday, missingNight: 0.3, splitNight: 0.3),
      seeds: n,
    );
    scenario(
      'Coffee at random beside Cigarettes 8 a day',
      (seed) => waking(seed, midday, frequent: const {'Cigarettes': 8}),
      seeds: n,
    );
    scenario(
      'Cigarettes 8 a day',
      (seed) => waking(seed, midday, frequent: const {'Cigarettes': 8}),
      seeds: n,
      habit: 'Cigarettes',
    );
    scenario(
      'Cigarettes 2 a day',
      (seed) => waking(seed, midday, frequent: const {'Cigarettes': 2}),
      seeds: n,
      habit: 'Cigarettes',
    );
    scenario(
      'Coffee at 22:30, bed at 23:00',
      (seed) => waking(seed, atBedtime),
      seeds: n,
    );
    scenario(
      '+3 bpm at 60-120, Coffee 2-3 h after waking',
      (seed) => waking(
        seed,
        laterAfterWaking,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 3 : 0,
      ),
      seeds: n,
    );
    scenario(
      '+3 bpm at 60-120, Coffee at random',
      (seed) => waking(
        seed,
        midday,
        effect: (h, m) => h == 'Coffee' && m >= 60 && m < 120 ? 3 : 0,
      ),
      seeds: n,
    );
    for (final bool lieIn in <bool>[true, false]) {
      int reports = 0, shown = 0;
      for (int seed = 0; seed < 40; seed++) {
        final Synthetic s = waking(seed, afterWaking, lieIn: lieIn);
        final InsightsReport report = computeInsights(
          InsightsInput(
            uses: s.uses,
            outcomes: const <DailyOutcome>[],
            from: syntheticStart,
            through: s.through,
            samples: s.samples,
          ),
        );
        final int h = report.findings
            .where((f) => f.kind == InsightKind.hoursAfter)
            .length;
        if (h > 0) reports++;
        shown += h;
      }
      stdout.writeln(
        'Coffee 15-60 min after waking, lie-in $lieIn, whole report: '
        '$reports of 40 reports with an hours-after finding, $shown in all',
      );
    }
  });

  test('hours after a use, waking from steps', () {
    const int n = 40;
    for (final (String name, UsePolicy p) in <(String, UsePolicy)>[
      ('Coffee 15-60 min after waking', afterWaking),
      ('Coffee 1-2 h after waking', anHourAfterWaking),
      ('Coffee 2-3 h after waking', laterAfterWaking),
      ('Coffee at 22:30, bed at 23:00', atBedtime),
      ('Coffee 09:00-15:00 at random', midday),
    ]) {
      scenario(
        '$name, no nights, steps 0-30 min after waking',
        (seed) => waking(seed, p, missingNight: 1, stepLag: 30),
        seeds: n,
      );
    }
    scenario(
      'Coffee 1-2 h after waking, nights recorded',
      (seed) => waking(seed, anHourAfterWaking, stepLag: 30),
      seeds: n,
    );
    for (final (String name, UsePolicy p) in <(String, UsePolicy)>[
      ('Coffee 15-60 min after waking', afterWaking),
      ('Coffee 1-2 h after waking', anHourAfterWaking),
      ('Coffee at 22:30', atBedtime),
    ]) {
      int reports = 0, shown = 0;
      for (int seed = 0; seed < n; seed++) {
        final Synthetic s = waking(seed, p, missingNight: 1, stepLag: 30);
        final InsightsReport report = computeInsights(
          InsightsInput(
            uses: s.uses,
            outcomes: const <DailyOutcome>[],
            from: syntheticStart,
            through: s.through,
            samples: s.samples,
          ),
        );
        final int h = report.findings
            .where((f) => f.kind == InsightKind.hoursAfter)
            .length;
        if (h > 0) reports++;
        shown += h;
      }
      stdout.writeln(
        '$name, no nights, waking from steps, whole report: '
        '$reports of $n reports with an hours-after finding, $shown in all',
      );
    }
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
        plan: insightsHoursAfterPlan(
          input.uses,
          s.through,
          bed: s.samples[HealthSampleMetric.bed.id]!,
        ),
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
