// Monte Carlo rates for the replacement comparison in
// lib/insights/replacement.dart (one habit rising as another falls), on
// synthetic journals only. Slow, so it lives outside test/:
//   flutter test tools/insights-calibration/replacement_test.dart
// Each line prints the share of seeds where a fall of Cigarettes was found,
// then, of the Vape checks fitted at that fall: the share whose step alone
// reads as a rise (interval above zero, before any other gate: the rate a
// plain step test would give), the share that is a finding before the
// false-discovery correction, and the share each later gate refused.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/replacement.dart';

import '../../test/insights/hours_after_synthetic.dart';
import '../../test/insights/replacement_synthetic.dart';

const int seeds = 400;

String pct(int n, int of) =>
    of == 0 ? 'none' : '${(100 * n / of).toStringAsFixed(1)}%';

bool weekend(int day) => addDays(syntheticStart, day).weekday >= 6;

void run(String name, ReplacementDays Function(int seed) make) {
  int falls = 0, fitted = 0, step = 0, found = 0;
  final Map<ReplacementRefusal, int> refused = <ReplacementRefusal, int>{};
  for (int seed = 0; seed < seeds; seed++) {
    final ReplacementDays d = make(seed);
    final List<Replacement> results = replacement(
      uses: d.uses,
      through: d.through,
    );
    if (results.any((Replacement r) => r.habitId == 'Cigarettes')) falls++;
    for (final Replacement r in results) {
      if (r.habitId != 'Cigarettes' || r.pValue == null) continue;
      fitted++;
      if (r.interval!.low > 0) step++;
      if (r.found) found++;
      if (r.refusal case final ReplacementRefusal reason) {
        refused[reason] = (refused[reason] ?? 0) + 1;
      }
    }
  }
  int of(ReplacementRefusal reason) => refused[reason] ?? 0;
  stdout.writeln(
    '$name ($seeds seeds): fall found ${pct(falls, seeds)}; of $fitted '
    'fitted, step alone ${pct(step, fitted)}, found ${pct(found, fitted)}; '
    'refused as already moving '
    '${pct(of(ReplacementRefusal.alreadyMoving), fitted)}, not then '
    '${pct(of(ReplacementRefusal.notThen), fitted)}, same last year '
    '${pct(of(ReplacementRefusal.sameLastYear), fitted)}',
  );
}

// A count a day that comes in runs: on a day in a run, Poisson [rate];
// otherwise nothing.
int Function(int day, Random r) binges(double rate) {
  final Map<Random, bool> on = <Random, bool>{};
  return (int day, Random r) {
    final bool now = r.nextDouble() < ((on[r] ?? false) ? 0.7 : 0.1);
    on[r] = now;
    return now ? poisson(r, rate) : 0;
  };
}

// A daily rate that wanders: [rate] times the exponential of an AR(1) at
// 0.97 with sd [sd].
int Function(int day, Random r) wandering(double rate, double sd) {
  final Map<Random, double> level = <Random, double>{};
  return (int day, Random r) {
    final double z =
        0.97 * (level[r] ?? gaussian(r)) + sqrt(1 - 0.97 * 0.97) * gaussian(r);
    level[r] = z;
    return poisson(r, rate * exp(sd * z));
  };
}

void main() {
  test('a fall with nothing rising for it: noise', () {
    run(
      '2 a day, steady',
      (s) => replacementDays(s, riser: (_, r) => poisson(r, 2)),
    );
    run(
      'about once a week',
      (s) => replacementDays(s, riser: (_, r) => poisson(r, 1 / 7)),
    );
    run(
      'every other day or so',
      (s) => replacementDays(s, riser: (_, r) => poisson(r, 0.5)),
    );
    run(
      'Saturdays only, about 3',
      (s) => replacementDays(
        s,
        riser: (i, r) =>
            addDays(syntheticStart, i).weekday == 6 ? poisson(r, 3) : 0,
      ),
    );
    run(
      'weekends only, about 4 a day',
      (s) =>
          replacementDays(s, riser: (i, r) => weekend(i) ? poisson(r, 4) : 0),
    );
    run('in runs (binges of about 5 a day)', (s) {
      return replacementDays(s, riser: binges(5));
    });
    run('a slow wander (AR(1) 0.97, sd 0.3 of the log rate)', (s) {
      return replacementDays(s, riser: wandering(2, 0.3));
    });
    run('a slow wander (AR(1) 0.97, sd 0.6 of the log rate)', (s) {
      return replacementDays(s, riser: wandering(2, 0.6));
    });
    run(
      'a year, 2 a day, steady',
      (s) => replacementDays(
        s,
        days: 365,
        fallAt: 274,
        riser: (_, r) => poisson(r, 2),
      ),
    );
    run(
      'a fall 5 weeks ago, 2 a day, steady',
      (s) => replacementDays(s, days: 126, riser: (_, r) => poisson(r, 2)),
    );
  });

  test('both following the calendar', () {
    run(
      'Cigarettes on weekdays only, Vape at weekends only',
      (s) => replacementDays(
        s,
        fallenShape: (i) => weekend(i) ? 0 : 1,
        riser: (i, r) => weekend(i) ? poisson(r, 4) : 0,
      ),
    );
    run(
      'Vape drifting up all along (1 a day to 3 over the 26 weeks)',
      (s) => replacementDays(s, riser: (i, r) => poisson(r, 1 + 2 * i / 182)),
    );
    run(
      'Vape drifting up over a year (1 a day to 3), the fall 13 weeks back',
      (s) => replacementDays(
        s,
        days: 365,
        fallAt: 274,
        riser: (i, r) => poisson(r, 1 + 2 * i / 365),
      ),
    );
    for (final int years in <int>[1, 2]) {
      run(
        'opposite seasons and no other fall, $years year'
        '${years == 1 ? '' : 's'} (Cigarettes 3 a day swinging by half, '
        'Vape 2 a day swinging the other way)',
        (s) => replacementDays(
          s,
          days: 365 * years,
          fallAt: null,
          fallenShape: (i) => 1 + 0.5 * cos(2 * pi * (i - 230) / 365),
          riser: (i, r) =>
              poisson(r, 2 * (1 - 0.5 * cos(2 * pi * (i - 230) / 365))),
        ),
      );
    }
    run(
      'a step of Vape\'s own (1 a day to 2.5) on a day of its own (known '
      'limit: it lands within the fortnight by coincidence)',
      (s) {
        final int at = 28 + Random(s + 5000).nextInt(182 - 56);
        return replacementDays(
          s,
          riser: (i, r) => poisson(r, i < at ? 1 : 2.5),
        );
      },
    );
  });

  test('a planted rise: power', () {
    run(
      '1 a day to 2 at the fall',
      (s) => replacementDays(s, riser: (i, r) => poisson(r, i < 91 ? 1 : 2)),
    );
    run(
      '2 a day to 3 at the fall',
      (s) => replacementDays(s, riser: (i, r) => poisson(r, i < 91 ? 2 : 3)),
    );
    run(
      '1 a day to 2 a week after the fall',
      (s) => replacementDays(s, riser: (i, r) => poisson(r, i < 98 ? 1 : 2)),
    );
    run(
      'first entries at the fall, about 2 a day',
      (s) => replacementDays(s, riser: (i, r) => i < 91 ? 0 : poisson(r, 2)),
    );
    run(
      'first entries at the fall, every other day or so',
      (s) => replacementDays(s, riser: (i, r) => i < 91 ? 0 : poisson(r, 0.5)),
    );
    run(
      '1 a day to 2.5 at a fall 6 weeks ago',
      (s) => replacementDays(
        s,
        days: 133,
        riser: (i, r) => poisson(r, i < 91 ? 1 : 2.5),
      ),
    );
    run(
      'weekends only, about 2 a day to 4 at the fall',
      (s) => replacementDays(
        s,
        riser: (i, r) => weekend(i) ? poisson(r, i < 91 ? 2 : 4) : 0,
      ),
    );
  });

  test('whole page on noise', () {
    int raw = 0, checks = 0, kept = 0, reports = 0;
    for (int seed = 0; seed < seeds; seed++) {
      final Random r = Random(seed + 9000);
      final ReplacementDays d = replacementDays(
        seed,
        riser: (_, r) => poisson(r, 2),
      );
      final List<HabitUse> uses = <HabitUse>[
        ...d.uses,
        ...usesOf('Tea', <int>[
          for (int i = 0; i < 182; i++)
            r.nextDouble() < 0.5 ? 1 + r.nextInt(4) : 0,
        ]),
        ...usesOf('Water', <int>[for (int i = 0; i < 182; i++) 1 + r.nextInt(4)]),
      ];
      final List<DailyOutcome> outcomes = <DailyOutcome>[
        for (int i = 0; i < 182; i++)
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
              ])
            DailyOutcome(
              date: addDays(syntheticStart, i),
              metricId: id,
              value: mid + sd * gaussian(r),
            ),
      ];
      final InsightsReport report = computeInsights(
        InsightsInput(
          uses: uses,
          outcomes: outcomes,
          from: syntheticStart,
          through: addDays(d.through, 1),
        ),
      );
      for (final Replacement p in report.replacements) {
        if (p.pValue == null) continue;
        checks++;
        if (p.found) kept++;
        if (p.found || p.refusal == ReplacementRefusal.chance) raw++;
      }
      if (report.replacements.any((Replacement p) => p.found)) reports++;
    }
    stdout.writeln(
      'whole page on noise ($seeds seeds, $checks replacement checks): '
      'found before the family ${pct(raw, checks)}, after it '
      '${pct(kept, checks)}; reports with a replacement finding '
      '${pct(reports, seeds)}',
    );
  });
}
