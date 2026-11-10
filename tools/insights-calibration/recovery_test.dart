// Monte Carlo rates for recovery after a heavy day in
// lib/insights/recovery.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/recovery_test.dart
// Each line prints, per measure, the share of seeds with a finding before the
// false-discovery correction and the floor, then each night's share of fitted
// seeds clearly off and shown back within the floor (half an sd), then how
// the findings read.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/what_follows.dart';

import '../../test/insights/hours_after_synthetic.dart';
import '../../test/insights/recovery_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) =>
    of == 0 ? '-' : '${(100 * n / of).toStringAsFixed(1)}%';

void rates(String name, RecoveryDays Function(int seed) make) {
  stdout.writeln('$name ($seeds seeds):');
  final Map<String, int> found = <String, int>{};
  final Map<String, int> fitted = <String, int>{};
  final Map<String, List<int>> off = <String, List<int>>{};
  final Map<String, List<int>> back = <String, List<int>>{};
  final Map<String, Map<String, int>> reads = <String, Map<String, int>>{};
  final Map<String, Map<RefusalReason, int>> unfitted =
      <String, Map<RefusalReason, int>>{};
  for (int seed = 0; seed < seeds; seed++) {
    final RecoveryDays d = make(seed);
    for (final Recovery r in recoveryAfterHeavyDays(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      through: d.through,
      floors: syntheticFloors,
    )) {
      final String m = r.metricId;
      if (r.nights.isEmpty) {
        final Map<RefusalReason, int> why = unfitted.putIfAbsent(
          m,
          () => <RefusalReason, int>{},
        );
        why[r.refusal!] = (why[r.refusal!] ?? 0) + 1;
        continue;
      }
      fitted[m] = (fitted[m] ?? 0) + 1;
      final List<int> offs = off.putIfAbsent(
        m,
        () => List<int>.filled(recoveryNights, 0),
      );
      final List<int> backs = back.putIfAbsent(
        m,
        () => List<int>.filled(recoveryNights, 0),
      );
      for (int k = 0; k < recoveryNights; k++) {
        if (r.nights[k].off) offs[k]++;
        if (r.nights[k].back) backs[k]++;
      }
      if (!r.found) continue;
      found[m] = (found[m] ?? 0) + 1;
      final String read = 'off ${r.offNights} back by ${r.backBy ?? '?'}';
      final Map<String, int> tally = reads.putIfAbsent(
        m,
        () => <String, int>{},
      );
      tally[read] = (tally[read] ?? 0) + 1;
    }
  }
  for (final String m in recoveryMetrics) {
    final int n = fitted[m] ?? 0;
    final List<String> nights = <String>[
      for (int k = 0; k < recoveryNights; k++)
        'night ${k + 1} off ${pct(off[m]?[k] ?? 0, n)} '
            'back ${pct(back[m]?[k] ?? 0, n)}',
    ];
    final List<String> sorted = (reads[m] ?? const <String, int>{}).entries
        .map((MapEntry<String, int> e) => '${e.key}: ${e.value}')
        .toList();
    stdout.writeln(
      '    $m: found ${pct(found[m] ?? 0, seeds)} ($n fitted); '
      '${nights.join('; ')}'
      '${sorted.isEmpty ? '' : '; findings {${sorted.join(', ')}}'}'
      '${unfitted[m] == null ? '' : '; unfitted ${unfitted[m]}'}',
    );
  }
}

void main() {
  test('noise', () {
    rates('independent days', (s) => recoveryDays(s));
    rates('60 days', (s) => recoveryDays(s, days: 60));
    rates('365 days', (s) => recoveryDays(s, days: 365));
    rates(
      'measures AR(1) 0.6, use in runs',
      (s) => recoveryDays(s, ar: 0.6, runs: true),
    );
    rates(
      'a short night brings a heavier day, AR(1) 0.6',
      (s) => recoveryDays(s, ar: 0.6, reverse: 1),
    );
    rates(
      'a short night brings a heavier day, independent days',
      (s) => recoveryDays(s, reverse: 1),
    );
    rates(
      'heavy Fridays and Saturdays, long weekend nights',
      (s) => recoveryDays(s, weekends: true),
    );
    rates(
      'a fifth of days missing, AR(1) 0.6',
      (s) => recoveryDays(s, ar: 0.6, missing: 0.2),
    );
  });

  test('not noise, by design: any use costs 1 sd, a heavy day no more', () {
    rates('any use 1 sd', (s) => recoveryDays(s, anyUse: 1));
  });

  test('power and how the nights read', () {
    rates(
      'a heavy day costs 1 sd for one night',
      (s) => recoveryDays(s, costs: <double>[1]),
    );
    rates(
      '1 sd then 0.5 sd (the floor)',
      (s) => recoveryDays(s, costs: <double>[1, 0.5]),
    );
    rates(
      '1 sd for two nights: "back by the second" is false',
      (s) => recoveryDays(s, costs: <double>[1, 1]),
    );
    rates(
      '1 sd for two nights, AR(1) 0.6, in runs',
      (s) => recoveryDays(s, costs: <double>[1, 1], ar: 0.6, runs: true),
    );
    rates(
      '0.5 sd for one night',
      (s) => recoveryDays(s, costs: <double>[0.5]),
    );
    rates(
      '1 sd for one night, 60 days',
      (s) => recoveryDays(s, days: 60, costs: <double>[1]),
    );
    rates(
      '1 sd for two nights, 365 days',
      (s) => recoveryDays(s, days: 365, costs: <double>[1, 1]),
    );
  });

  test('whole page', () {
    void page(String name, List<double> costs) {
      int kept = 0, checks = 0, reports = 0;
      for (int seed = 0; seed < seeds; seed++) {
        final RecoveryDays d = recoveryDays(seed, costs: costs);
        final Random r = Random(seed + 100000);
        final List<HabitUse> uses = <HabitUse>[...d.uses];
        for (int i = 0; i < 120; i++) {
          final DateTime day = addDays(syntheticStart, i);
          for (final (String habit, double chance) in <(String, double)>[
            ('Coffee', 0.6),
            ('Tea', 0.5),
          ]) {
            if (r.nextDouble() >= chance) continue;
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
        }
        final InsightsReport report = computeInsights(
          InsightsInput(
            uses: uses,
            outcomes: d.outcomes,
            from: syntheticStart,
            through: d.through,
          ),
        );
        checks += report.recovery.where((x) => x.nights.isNotEmpty).length;
        final int found = report.recovery.where((x) => x.found).length;
        kept += found;
        if (found > 0) reports++;
      }
      stdout.writeln(
        '$name ($seeds seeds, three habits, $checks recovery checks fitted): '
        'findings after the family and floors ${pct(kept, checks)} of '
        'checks; reports with a recovery finding ${pct(reports, seeds)}',
      );
    }

    page('whole page on noise', const <double>[]);
    page('whole page, Beer costs 1 sd for two nights', const <double>[1, 1]);
  });
}
