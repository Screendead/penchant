import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart'
    show HabitFinding, InsightKind;

// Health values stay on the device: nothing here is logged or reported.

/// When a habit counts as fallen, and when a measure since is reported
/// rather than refused. Not tuned on anyone's data; the rates they give on
/// synthetic days are measured in `tools/insights-calibration/payoff_test.dart`.
class PayoffGates {
  const PayoffGates({
    this.baselineDays = 91,
    this.minBaselineDays = 28,
    this.sinceDays = 91,
    this.minSinceDays = 28,
    this.recentDays = 14,
    this.minFall = 0.25,
    this.fallSignificance = 0.01,
    this.sameFallDays = 14,
    this.minBaselineValues = 21,
    this.minSinceValues = 14,
    this.minResidualDays = 10,
    this.minAutocorrelationPairs = 14,
    this.maxAutocorrelation = 0.9,
    this.correctAutocorrelationBias = true,
    this.level = 0.95,
    this.falseDiscoveryRate = 0.1,
  });

  /// The most days before the fall that count as the old baseline, and the
  /// fewest the journal must hold.
  final int baselineDays;
  final int minBaselineDays;

  /// The most days after the fall a measure is read over, so the comparison
  /// stays near enough to the change for a straight trend to stand in for
  /// the season.
  final int sinceDays;

  /// The fewest days a habit must have stayed lower.
  final int minSinceDays;

  /// The latest days, which must be as far under the baseline as the whole
  /// time since.
  final int recentDays;

  /// The smallest fall, as a share of the baseline's daily mean.
  final double minFall;

  /// One-sided, for the weekly totals since against the baseline's.
  final double fallSignificance;

  /// Two habits whose falls are this many days apart or fewer cannot be told
  /// apart.
  final int sameFallDays;

  /// The fewest days with a value of the measure, before and since.
  final int minBaselineValues;
  final int minSinceValues;

  /// The fewest days the model must have beyond its columns.
  final int minResidualDays;

  /// The fewest pairs of next-door days the day-to-day carry-over is
  /// estimated from; with fewer it is taken as none.
  final int minAutocorrelationPairs;
  final double maxAutocorrelation;

  /// Whether the carry-over estimated from residuals, which runs low by
  /// about (columns x (1 + it) + 2 x it) / pairs, is raised by that much.
  final bool correctAutocorrelationBias;
  final double level;

  /// Benjamini-Hochberg's q across every comparison in one report.
  final double falseDiscoveryRate;
}

/// A habit's daily amount falling and staying lower, found from its entries
/// alone: no measure is looked at to place it.
class HabitFall {
  const HabitFall({
    required this.habitId,
    required this.day,
    required this.from,
    required this.before,
    required this.since,
    required this.sinceDays,
  });

  final String habitId;

  /// The first day at the lower level.
  final DateTime day;

  /// The first day of the baseline.
  final DateTime from;

  /// The mean a day over the baseline, and from [day] on.
  final double before;
  final double since;

  /// The days from [day] to the last whole day.
  final int sinceDays;

  /// No entry at all since [day]: the journal cannot tell a habit given up
  /// from one no longer logged.
  bool get stopped => since == 0;
}

enum PayoffRefusal {
  /// Too few days with a value before the fall or since it.
  tooFewDays,

  /// [Payoff.otherHabitId] fell within [PayoffGates.sameFallDays] of this
  /// habit, so a change since belongs to neither alone. Nothing is fitted.
  otherFall,

  /// The interval for the change includes zero.
  withinNoise,

  /// The interval excludes zero, but the same model finds a change halfway
  /// through the baseline, where the habit had not moved: the measure shifts
  /// on its own by more than a straight trend allows for.
  alreadyMoving,

  /// Does not stand out among every comparison in the report. Set by the
  /// report.
  chance,

  /// Under the measure's smallest difference worth showing. Set by the
  /// report, after [chance].
  tooSmall,
}

/// One measure since a habit fell against its level before: a finding when
/// [refusal] is null.
class Payoff {
  const Payoff({
    required this.fall,
    required this.metricId,
    required this.baselineValues,
    required this.sinceValues,
    required this.capped,
    this.effect,
    this.interval,
    this.pValue,
    this.autocorrelation,
    this.refusal,
    this.otherHabitId,
  });

  final HabitFall fall;
  final String metricId;

  /// Days with a value of the measure in the baseline, and since the fall.
  final int baselineValues;
  final int sinceValues;

  /// Whether the time since the fall runs past [PayoffGates.sinceDays], so
  /// only that many days after it are read.
  final bool capped;

  /// The measure's level since the fall less its level before, in its units.
  final double? effect;
  final Interval? interval;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;

  /// The day-to-day carry-over the fit allowed for.
  final double? autocorrelation;
  final PayoffRefusal? refusal;
  final String? otherHabitId;

  String get habitId => fall.habitId;
  bool get found => refusal == null;

  Payoff refused(PayoffRefusal reason) => Payoff(
    fall: fall,
    metricId: metricId,
    baselineValues: baselineValues,
    sinceValues: sinceValues,
    capped: capped,
    effect: effect,
    interval: interval,
    pValue: pValue,
    autocorrelation: autocorrelation,
    refusal: reason,
    otherHabitId: otherHabitId,
  );

  /// As a [HabitFinding], for the sizing and wording any finding gets. Only
  /// for a fitted result.
  HabitFinding get asFinding => HabitFinding(
    habitId: habitId,
    metricId: metricId,
    lagDays: 0,
    usableDays: baselineValues + sinceValues,
    exposedDays: sinceValues,
    raw: null,
    kind: InsightKind.use,
    step: 1,
    effect: effect!,
    interval: interval!,
    standardized: 0,
    pValue: pValue!,
  );
}

/// Each habit's fall, for those with one: the day that best splits its daily
/// totals, a day with no entry counting as zero, into a baseline (up to
/// [PayoffGates.baselineDays] before it) and a lower level kept from then to
/// [through], the last whole day.
///
/// A day qualifies when the mean since it, and the mean of the latest
/// [PayoffGates.recentDays], are both at least [PayoffGates.minFall] under
/// the baseline's, and the weekly totals since are lower than the baseline's
/// weeks by a one-sided Welch test at [PayoffGates.fallSignificance]. Weeks
/// rather than days, since use differs by weekday and comes in runs. Among
/// the days that qualify, the one with the largest test statistic, the
/// earliest on a tie.
Map<String, HabitFall> findFalls(
  DailyHabitSeries habits,
  DateTime through, {
  PayoffGates gates = const PayoffGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<String, HabitFall> falls = <String, HabitFall>{};
  for (final String id in habits.habitIds) {
    final DateTime? first = habits.firstUse(id);
    if (first == null) continue;
    final List<DateTime> days = daysFrom(first, last).toList();
    final int n = days.length;
    final List<double> sums = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      sums[i + 1] = sums[i] + habits.total(id, days[i]);
    }
    double best = 0;
    HabitFall? fall;
    for (int c = gates.minBaselineDays; c <= n - gates.minSinceDays; c++) {
      final int from = max(0, c - gates.baselineDays);
      final double before = (sums[c] - sums[from]) / (c - from);
      final double since = (sums[n] - sums[c]) / (n - c);
      final double recent =
          (sums[n] - sums[n - gates.recentDays]) / gates.recentDays;
      final double limit = (1 - gates.minFall) * before;
      if (before <= 0 || since > limit || recent > limit) continue;
      final List<double> weeksBefore = <double>[
        for (int end = c; end - 7 >= from; end -= 7) sums[end] - sums[end - 7],
      ];
      final List<double> weeksSince = <double>[
        for (int start = c; start + 7 <= n; start += 7)
          sums[start + 7] - sums[start],
      ];
      if (weeksBefore.length < 2 || weeksSince.length < 2) continue;
      final double a = sampleVariance(weeksBefore) / weeksBefore.length;
      final double b = sampleVariance(weeksSince) / weeksSince.length;
      final double difference = mean(weeksBefore) - mean(weeksSince);
      if (difference <= 0) continue;
      final double t = a + b == 0 ? double.infinity : difference / sqrt(a + b);
      if (t <= best) continue;
      if (a + b > 0) {
        final double df =
            (a + b) *
            (a + b) /
            (a * a / (weeksBefore.length - 1) +
                b * b / (weeksSince.length - 1));
        if (1 - studentTCdf(t, df) >= gates.fallSignificance) continue;
      }
      best = t;
      fall = HabitFall(
        habitId: id,
        day: days[c],
        from: days[from],
        before: before,
        since: since,
        sinceDays: n - c,
      );
    }
    if (fall != null) falls[id] = fall;
  }
  return falls;
}

/// For each habit not in [skip] that [findFalls] gives a fall, each of
/// [metricIds] since the fall against the baseline before it.
///
/// One model per measure over the days from the baseline's start to
/// [PayoffGates.sinceDays] after the fall, the fall's own day left out (a
/// night's sleep belongs to the day before it, a day's average to both
/// sides): a level, a step at the fall, a straight trend across both sides
/// and whether the day is a weekend day. The trend is what a drift or a
/// season's slope over those months would otherwise lend the step. The
/// errors are taken to carry over from each day to the next (AR(1), fitted
/// by generalised least squares, a gap of days carrying over that much
/// less), since a step is as
/// persistent a column as there is and independent errors would understate
/// its standard error several times over.
///
/// A habit whose fall comes within [PayoffGates.sameFallDays] of another
/// habit's, archived or not, is refused unfitted as
/// [PayoffRefusal.otherFall]: holding the other's use fixed would not tell
/// two steps at one time apart.
List<Payoff> payoff({
  required List<HabitUse> uses,
  required OutcomeSeries outcomes,
  required List<String> metricIds,
  required DateTime through,
  Set<String> skip = const <String>{},
  PayoffGates gates = const PayoffGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<String, HabitFall> falls = findFalls(
    DailyHabitSeries.fromUses(uses),
    last,
    gates: gates,
  );
  final List<String> ids = falls.keys.toList()..sort();
  final List<Payoff> out = <Payoff>[];
  for (final String id in ids) {
    if (skip.contains(id)) continue;
    final HabitFall fall = falls[id]!;
    String? other;
    for (final String otherId in ids) {
      if (otherId != id &&
          daysBetween(fall.day, falls[otherId]!.day).abs() <=
              gates.sameFallDays) {
        other = otherId;
        break;
      }
    }
    for (final String metricId in metricIds) {
      out.add(
        other == null
            ? _judge(fall, metricId, outcomes, last, gates)
            : Payoff(
                fall: fall,
                metricId: metricId,
                baselineValues: 0,
                sinceValues: 0,
                capped: fall.sinceDays > gates.sinceDays,
                refusal: PayoffRefusal.otherFall,
                otherHabitId: other,
              ),
      );
    }
  }
  return out;
}

Payoff _judge(
  HabitFall fall,
  String metricId,
  OutcomeSeries outcomes,
  DateTime last,
  PayoffGates gates,
) {
  final DateTime windowEnd = addDays(fall.day, gates.sinceDays);
  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[];
  for (final DateTime day in daysFrom(
    fall.from,
    windowEnd.isAfter(last) ? last : windowEnd,
  )) {
    if (day == fall.day) continue;
    final double? value = outcomes.value(metricId, day);
    if (value == null) continue;
    days.add(day);
    y.add(value);
  }
  final int before = days.where((d) => d.isBefore(fall.day)).length;
  Payoff result({
    PayoffRefusal? refusal,
    double? effect,
    Interval? interval,
    double? pValue,
    double? autocorrelation,
  }) => Payoff(
    fall: fall,
    metricId: metricId,
    baselineValues: before,
    sinceValues: days.length - before,
    capped: fall.sinceDays > gates.sinceDays,
    effect: effect,
    interval: interval,
    pValue: pValue,
    autocorrelation: autocorrelation,
    refusal: refusal,
  );
  if (before < gates.minBaselineValues ||
      days.length - before < gates.minSinceValues) {
    return result(refusal: PayoffRefusal.tooFewDays);
  }
  final ({LinearFit fit, double autocorrelation})? fitted = _stepFit(
    days,
    y,
    before,
    fall.day,
    gates,
  );
  if (fitted == null) return result(refusal: PayoffRefusal.tooFewDays);
  final Interval interval = fitted.fit.interval(1, level: gates.level);
  PayoffRefusal? refusal;
  if (interval.crossesZero) {
    refusal = PayoffRefusal.withinNoise;
  } else if (before >= 2 * gates.minSinceValues) {
    final ({LinearFit fit, double autocorrelation})? placebo = _stepFit(
      days.sublist(0, before),
      y.sublist(0, before),
      before ~/ 2,
      days[before ~/ 2],
      gates,
    );
    if (placebo != null &&
        !placebo.fit.interval(1, level: gates.level).crossesZero) {
      refusal = PayoffRefusal.alreadyMoving;
    }
  }
  return result(
    refusal: refusal,
    effect: fitted.fit.coefficients[1],
    interval: interval,
    pValue: fitted.fit.pValue(1),
    autocorrelation: fitted.autocorrelation,
  );
}

// [y] on a level, a step from row [stepAt] on, a trend in days from [origin]
// and the weekend, with AR(1) errors; coefficient 1 is the step. Null when
// the design is singular or leaves too few days beyond its columns.
({LinearFit fit, double autocorrelation})? _stepFit(
  List<DateTime> days,
  List<double> y,
  int stepAt,
  DateTime origin,
  PayoffGates gates,
) {
  final List<double> weekend = <double>[
    for (final DateTime d in days) d.weekday >= 6 ? 1 : 0,
  ];
  final bool withWeekend = sampleVariance(weekend) > 1e-12;
  final List<List<double>> design = <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[
        1,
        r >= stepAt ? 1 : 0,
        daysBetween(origin, days[r]) / gates.baselineDays,
        if (withWeekend) weekend[r],
      ],
  ];
  final int columns = design.first.length;
  if (days.length - columns < gates.minResidualDays) return null;
  final List<bool> follows = <bool>[
    for (int r = 0; r < days.length; r++)
      r > 0 && daysBetween(days[r - 1], days[r]) == 1,
  ];
  final int pairs = follows.where((f) => f).length;
  LinearFit? fit = fitLeastSquares(design, y);
  double phi = 0;
  for (int pass = 0; fit != null && pass < 3; pass++) {
    if (pairs < gates.minAutocorrelationPairs) break;
    final List<double> e = <double>[
      for (int r = 0; r < y.length; r++)
        y[r] -
            <double>[
              for (int j = 0; j < columns; j++)
                design[r][j] * fit.coefficients[j],
            ].fold<double>(0, (s, v) => s + v),
    ];
    double lagged = 0, squares = 0;
    for (int r = 1; r < e.length; r++) {
      if (!follows[r]) continue;
      lagged += e[r] * e[r - 1];
      squares += (e[r] * e[r] + e[r - 1] * e[r - 1]) / 2;
    }
    double estimate = squares == 0 ? 0 : lagged / squares;
    if (gates.correctAutocorrelationBias && pairs > columns + 2) {
      estimate = (pairs * estimate + columns) / (pairs - columns - 2);
    }
    phi = estimate.clamp(0.0, gates.maxAutocorrelation);
    // Each row less what the row before it predicts, across however many
    // days lie between them, scaled so every row's error has one variance.
    final List<double> carry = <double>[
      for (int r = 0; r < days.length; r++)
        r == 0 ? 0 : pow(phi, daysBetween(days[r - 1], days[r])).toDouble(),
    ];
    final List<double> weight = <double>[
      for (final double c in carry) sqrt((1 - phi * phi) / (1 - c * c)),
    ];
    fit = fitLeastSquares(
      <List<double>>[
        for (int r = 0; r < days.length; r++)
          <double>[
            for (int j = 0; j < columns; j++)
              weight[r] *
                  (design[r][j] - (r == 0 ? 0 : carry[r] * design[r - 1][j])),
          ],
      ],
      <double>[
        for (int r = 0; r < y.length; r++)
          weight[r] * (y[r] - (r == 0 ? 0 : carry[r] * y[r - 1])),
      ],
    );
  }
  return fit == null ? null : (fit: fit, autocorrelation: phi);
}

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside]: a finding that fails Benjamini-Hochberg at
/// [PayoffGates.falseDiscoveryRate] over them all is refused as
/// [PayoffRefusal.chance], then one under [sizeOf] 1 (its measure's floor)
/// as [PayoffRefusal.tooSmall].
List<Payoff> judgePayoffs(
  List<Payoff> results, {
  required List<double> alongside,
  required double Function(Payoff finding) sizeOf,
  PayoffGates gates = const PayoffGates(),
}) {
  final List<int> tested = <int>[
    for (int i = 0; i < results.length; i++)
      if (results[i].pValue != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) results[i].pValue!,
    ...alongside,
  ], gates.falseDiscoveryRate);
  final Set<int> chance = <int>{
    for (int k = 0; k < tested.length; k++)
      if (!kept[k]) tested[k],
  };
  return <Payoff>[
    for (int i = 0; i < results.length; i++)
      if (!results[i].found)
        results[i]
      else if (chance.contains(i))
        results[i].refused(PayoffRefusal.chance)
      else if (sizeOf(results[i]) < 1)
        results[i].refused(PayoffRefusal.tooSmall)
      else
        results[i],
  ];
}
