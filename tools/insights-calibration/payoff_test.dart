// Monte Carlo rates for the payoff-from-cutting-down comparison in
// lib/insights/payoff.dart, on synthetic data only. Slow, so it lives
// outside test/:
//   flutter test tools/insights-calibration/payoff_test.dart
// Each line prints the share of seeds where a fall was found in the journal,
// then, of the comparisons fitted, the share with a finding before the
// false-discovery correction and the floor, per measure, and the mean
// day-to-day carry-over the fit allowed for.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/payoff.dart';

import '../../test/insights/before_use_synthetic.dart';
import '../../test/insights/hours_after_synthetic.dart';
import '../../test/insights/payoff_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) =>
    of == 0 ? 'none' : '${(100 * n / of).toStringAsFixed(1)}%';

void run(
  String name,
  PayoffDays Function(int seed) make, {
  PayoffGates gates = const PayoffGates(),
}) {
  int falls = 0, fitted = 0, found = 0, moving = 0, offBy = 0;
  double phi = 0;
  final Map<String, int> byMetric = <String, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final PayoffDays d = make(seed);
    final List<Payoff> results = payoff(
      uses: d.uses,
      outcomes: OutcomeSeries.fromOutcomes(d.outcomes),
      metricIds: payoffMetrics,
      through: d.through,
      gates: gates,
    );
    if (results.isEmpty) continue;
    falls++;
    if (d.fallDay case final DateTime planted) {
      offBy += daysBetween(planted, results.first.fall.day).abs();
    }
    for (final Payoff p in results) {
      if (p.pValue == null) continue;
      fitted++;
      phi += p.autocorrelation!;
      if (p.refusal == PayoffRefusal.alreadyMoving) moving++;
      if (p.found) {
        found++;
        byMetric[p.metricId] = (byMetric[p.metricId] ?? 0) + 1;
      }
    }
  }
  stdout.writeln(
    '$name ($seeds seeds): fall found ${pct(falls, seeds)}'
    '${offBy > 0 ? ', ${(offBy / falls).toStringAsFixed(1)} days off' : ''}; '
    'of $fitted fitted, found ${pct(found, fitted)} '
    '(${[for (final String m in payoffMetrics) pct(byMetric[m] ?? 0, max(1, fitted ~/ 3))].join(' / ')}), '
    'already moving ${pct(moving, fitted)}, mean carry-over '
    '${fitted == 0 ? '-' : (phi / fitted).toStringAsFixed(2)}',
  );
}

void main() {
  test('a fall with nothing behind it: noise', () {
    run('independent days', (s) => payoffDays(s));
    run('AR(1) 0.6', (s) => payoffDays(s, ar: 0.6));
    run(
      'AR(1) 0.6, no bias correction',
      (s) => payoffDays(s, ar: 0.6),
      gates: const PayoffGates(correctAutocorrelationBias: false),
    );
    run('AR(1) 0.8', (s) => payoffDays(s, ar: 0.8));
    run(
      'a drift of 2 sd over the 26 weeks, AR(1) 0.6',
      (s) => payoffDays(s, ar: 0.6, drift: 2),
    );
    run(
      'a season of 0.5 sd, any time of year, AR(1) 0.6',
      (s) => payoffDays(s, ar: 0.6, season: 0.5),
    );
    run(
      'a season of 0.5 sd at its steepest on the fall, AR(1) 0.6',
      (s) => payoffDays(s, ar: 0.6, season: 0.5, seasonPhase: -0.25),
    );
    run(
      'a season of 1 sd at its steepest on the fall, independent days',
      (s) => payoffDays(s, season: 1, seasonPhase: -0.25),
    );
    run(
      'a slow wander (AR(1) 0.97) of 0.5 sd under independent days',
      (s) => payoffDays(s, wander: 0.5),
    );
    run(
      '30% of days missing, AR(1) 0.6',
      (s) => payoffDays(s, ar: 0.6, missing: 0.3),
    );
    run(
      'a fall 5 weeks ago, AR(1) 0.6',
      (s) => payoffDays(s, days: 126, ar: 0.6),
    );
    run(
      'a year, the fall 9 months back, AR(1) 0.6',
      (s) => payoffDays(s, days: 365, ar: 0.6),
    );
  });

  test('no fall at all', () {
    run('3 a day, steady', (s) => payoffDays(s, fallAt: null));
    run(
      'every other day or so, steady',
      (s) => payoffDays(s, fallAt: null, rateBefore: 0.5, rateAfter: 0.5),
    );
    run('a year at 3 a day', (s) => payoffDays(s, days: 365, fallAt: null));
    run('good nights lower use (before a use, reverse 1), 120 days', (s) {
      final BeforeDays d = beforeDays(s, reverse: 1);
      return (
        uses: d.uses,
        outcomes: d.outcomes,
        through: d.through,
        fallDay: null,
      );
    });
  });

  test('how soon a halving registers', () {
    for (final int weeks in <int>[4, 5, 6, 8]) {
      run(
        '3 a day to 1.5, $weeks weeks ago',
        (s) => payoffDays(s, days: 91 + 7 * weeks),
      );
    }
    run('3 a day to 2, 13 weeks ago', (s) => payoffDays(s, rateAfter: 2));
    run(
      'every other day to one in four, 13 weeks ago',
      (s) => payoffDays(s, rateBefore: 0.5, rateAfter: 0.25),
    );
  });

  test('a planted payoff: power', () {
    run('1 sd, independent days', (s) => payoffDays(s, shift: 1));
    run('0.5 sd, independent days', (s) => payoffDays(s, shift: 0.5));
    run('1 sd, AR(1) 0.6', (s) => payoffDays(s, ar: 0.6, shift: 1));
    run('2 sd, AR(1) 0.6', (s) => payoffDays(s, ar: 0.6, shift: 2));
    run(
      '1 sd, independent days, the fall 6 weeks ago',
      (s) => payoffDays(s, days: 133, shift: 1),
    );
  });

  test('whole page on noise', () {
    int raw = 0, checks = 0, kept = 0, reportsPayoff = 0, reportsAny = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final Random r = Random(seed);
      final PayoffDays coffee = payoffDays(seed);
      final List<HabitUse> uses = <HabitUse>[...coffee.uses];
      final List<DailyOutcome> outcomes = <DailyOutcome>[];
      for (int i = 0; i < 182; i++) {
        final DateTime day = addDays(syntheticStart, i);
        for (final (String habit, double chance) in <(String, double)>[
          ('Tea', 0.5),
          ('Water', 1),
        ]) {
          if (r.nextDouble() >= chance) continue;
          final int n = 1 + r.nextInt(4);
          for (int k = 0; k < n; k++) {
            uses.add(
              HabitUse(
                habitId: habit,
                at: day.add(Duration(minutes: 7 * 60 + 60 * k)),
                amount: 1,
              ),
            );
          }
        }
        for (final (String id, double mid, double sd)
            in <(String, double, double)>[
              ('sleepAsleep', 420, 40),
              ('sleepDeep', 70, 15),
              ('sleepREM', 90, 20),
              ('sleepCore', 240, 30),
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
      final DateTime last = addDays(syntheticStart, 181);
      final InsightsReport report = computeInsights(
        InsightsInput(
          uses: uses,
          outcomes: outcomes,
          from: syntheticStart,
          through: addDays(last, 1),
        ),
      );
      for (final Payoff p in report.payoffs) {
        if (p.pValue == null) continue;
        checks++;
        if (p.found) kept++;
        if (!p.interval!.crossesZero &&
            p.refusal != PayoffRefusal.alreadyMoving) {
          raw++;
        }
      }
      final bool any = report.payoffs.any((p) => p.found);
      if (any) reportsPayoff++;
      if (any ||
          report.findings.isNotEmpty ||
          report.beforeUse.any((b) => b.found)) {
        reportsAny++;
      }
    }
    stdout.writeln(
      'whole page on noise ($seeds seeds, $checks payoff checks): raw '
      '${pct(raw, checks)}, after the family and floors ${pct(kept, checks)}; '
      'reports with a payoff finding ${pct(reportsPayoff, seeds)}, with any '
      'finding ${pct(reportsAny, seeds)}',
    );
  });
}
