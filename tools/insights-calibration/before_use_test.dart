// Monte Carlo rates for the before-a-use comparisons in
// lib/insights/before_use.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/before_use_test.dart
// Each line prints the share of seeds with a finding before the
// false-discovery correction and the floor.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart' show HealthSampleMetric;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

import '../../test/insights/before_use_synthetic.dart';
import '../../test/insights/hours_after_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) => '${(100 * n / of).toStringAsFixed(1)}%';

void daily(String name, BeforeDays Function(int seed) make) {
  final Map<(BeforeUseKind, String), int> found =
      <(BeforeUseKind, String), int>{};
  final Map<RefusalReason, int> unfitted = <RefusalReason, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final BeforeDays d = make(seed);
    for (final BeforeUse b in beforeUse(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      through: d.through,
    )) {
      if (b.found) {
        found[(b.kind, b.metricId)] = (found[(b.kind, b.metricId)] ?? 0) + 1;
      } else if (b.pValue == null) {
        unfitted[b.refusal!] = (unfitted[b.refusal!] ?? 0) + 1;
      }
    }
  }
  stdout.writeln('$name ($seeds seeds):');
  for (final String metric in beforeUseMetrics) {
    stdout.writeln(
      '    $metric: ${[for (final k in BeforeUseKind.values.take(3)) '${k.name} ${pct(found[(k, metric)] ?? 0, seeds)}'].join(', ')}',
    );
  }
  if (unfitted.isNotEmpty) stdout.writeln('    refused unfitted: $unfitted');
}

void hour(String name, Synthetic Function(int seed) make, {int seeds = 200}) {
  int found = 0, higher = 0, fitted = 0;
  final Map<String, int> short = <String, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final Synthetic s = make(seed);
    for (final BeforeUse b in hourBefore(
      plan: planHoursAfter(
        s.uses,
        s.through,
        bed: s.samples[HealthSampleMetric.bed.id]!,
      ),
      uses: s.uses,
      samples: s.samples,
    )) {
      if (b.habitId != 'Coffee') continue;
      if (b.pValue != null) fitted++;
      if (b.found) {
        found++;
        if (b.effect! > 0) higher++;
      } else if (b.pValue == null) {
        short['${b.shortfall}'] = (short['${b.shortfall}'] ?? 0) + 1;
      }
    }
  }
  stdout.writeln(
    '$name ($seeds seeds, $fitted fitted): ${pct(found, seeds)} found, '
    '$higher of them higher${short.isEmpty ? '' : '; too few days $short'}',
  );
}

int? laterAfterWaking(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.85 ? wake + 120 + r.nextInt(60) : null;
int? weekdaysAtNine(int wake, bool weekend, List<double> w, Random r) =>
    weekend ? null : 9 * 60 + r.nextInt(30);
int? midday(int wake, bool weekend, List<double> w, Random r) =>
    r.nextDouble() < 0.7 ? 9 * 60 + 5 * r.nextInt(72) : null;
// Where the hour before runs lowest among 6 times from 10:00 to 15:00.
int? afterALowHour(int wake, bool weekend, List<double> w, Random r) {
  if (r.nextDouble() > 0.7) return null;
  double hourBefore(int m) {
    double sum = 0;
    for (int k = 1; k <= 12; k++) {
      sum += w[m ~/ 5 - k];
    }
    return sum;
  }

  int best = -1;
  for (int k = 0; k < 6; k++) {
    final int m = 10 * 60 + 5 * r.nextInt(60);
    if (best < 0 || hourBefore(m) < hourBefore(best)) best = m;
  }
  return best;
}

void main() {
  test('the night or day before: noise', () {
    daily('independent days', (seed) => beforeDays(seed));
    daily('60 days', (seed) => beforeDays(seed, days: 60));
    daily(
      'measures AR(1) 0.6, use in runs',
      (seed) => beforeDays(seed, ar: 0.6, runs: true),
    );
    daily(
      'use costs 1 sd that night and day, in runs, AR(1) 0.6: nothing comes '
      'before',
      (seed) => beforeDays(seed, ar: 0.6, runs: true, forward: 1),
    );
    daily(
      'a later waking is more sleep and a later first use',
      (seed) => beforeDays(seed, wakeLinked: 1),
    );
  });

  test('the night or day before: power on sleep', () {
    daily(
      'a night 1 sd short: 25 points more use, 1 more, 1 h earlier',
      (seed) => beforeDays(seed, reverse: 1),
    );
    daily('half of that', (seed) => beforeDays(seed, reverse: 0.5));
    daily(
      'half of that, 60 days',
      (seed) => beforeDays(seed, days: 60, reverse: 0.5),
    );
  });

  test('the hour before a use', () {
    Synthetic waking(int seed, UsePolicy coffee, {Map<String, int>? beside}) =>
        wakingSynthetic(
          seed,
          habits: <String, UsePolicy>{'Coffee': coffee},
          frequent: beside ?? const <String, int>{},
        );
    hour('noise, 2-3 h after waking', (s) => waking(s, laterAfterWaking));
    hour('noise, weekdays 09:00', (s) => waking(s, weekdaysAtNine));
    hour('noise, random 09:00-15:00', (s) => waking(s, midday));
    hour(
      'noise, beside Cigarettes 8 a day',
      (s) => waking(s, midday, beside: <String, int>{'Cigarettes': 8}),
    );
    hour(
      'noise, clock-tied climb, no sleep in the day',
      (s) => synthetic(s),
      seeds: seeds,
    );
    hour('used after the lowest of 6 hours', (s) => waking(s, afterALowHour));
  });

  test('whole page on noise', () {
    int raw = 0, checks = 0, kept = 0, reportsBefore = 0, reportsAny = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final Random r = Random(seed);
      final List<HabitUse> uses = <HabitUse>[];
      final List<DailyOutcome> outcomes = <DailyOutcome>[];
      for (int i = 0; i < 120; i++) {
        final DateTime day = addDays(syntheticStart, i);
        void use(String habit, double chance) {
          if (r.nextDouble() >= chance) return;
          final int n = 1 + r.nextInt(4);
          final int at = 6 * 60 + r.nextInt(300);
          for (int k = 0; k < n; k++) {
            uses.add(
              HabitUse(
                habitId: habit,
                at: day.add(Duration(minutes: at + 60 * k)),
                amount: 1,
              ),
            );
          }
        }

        use('Coffee', 0.6);
        use('Tea', 0.5);
        use('Water', 1);
        for (final (String id, double mid, double sd)
            in <(String, double, double)>[
              ('sleepAsleep', 420, 40),
              ('sleepDeep', 70, 15),
              ('sleepREM', 90, 20),
              ('sleepCore', 240, 30),
              ('sleepEnd', 19 * 60, 30),
              ('heartRateVariabilitySDNN', 45, 8),
              ('restingHeartRate', 58, 2),
              ('respiratoryRate', 14, 0.6),
              ('stepCount', 8000, 2500),
              ('activeEnergyBurned', 500, 150),
            ]) {
          outcomes.add(
            DailyOutcome(
              date: day,
              metricId: id,
              value: mid + sd * gaussian(r),
            ),
          );
        }
      }
      final DateTime last = addDays(syntheticStart, 119);
      final OutcomeSeries series = OutcomeSeries.fromOutcomes(outcomes);
      for (final BeforeUse b in beforeUse(
        uses: uses,
        outcomes: series,
        through: last,
      )) {
        if (b.pValue == null) continue;
        checks++;
        if (b.found) raw++;
      }
      final InsightsReport report = computeInsights(
        InsightsInput(
          uses: uses,
          outcomes: outcomes,
          from: syntheticStart,
          through: addDays(last, 1),
        ),
      );
      final int before = report.beforeUse.where((b) => b.found).length;
      kept += before;
      if (before > 0) reportsBefore++;
      if (before > 0 || report.findings.isNotEmpty) reportsAny++;
    }
    stdout.writeln(
      'whole page on noise ($seeds seeds, $checks before-use checks): raw '
      '${pct(raw, checks)}, after the family and floors ${pct(kept, checks)}; '
      'reports with a before-use finding ${pct(reportsBefore, seeds)}, with '
      'any finding ${pct(reportsAny, seeds)}',
    );
  });
}
