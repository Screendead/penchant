import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Health values stay on the device: nothing here is logged or reported.

/// The daily measures followed after a heavy day, as `HealthMetric.id`.
const List<String> recoveryMetrics = <String>[
  'sleepAsleep',
  'heartRateVariabilitySDNN',
  'restingHeartRate',
];

/// How many nights after a heavy day are followed.
const int recoveryNights = 3;

/// The amount a day's total must reach to be a heavy day among [totals], a
/// habit's totals on its days of use: the smallest of them at or over their
/// upper quartile and over their median. Null when no day is over the median
/// by that rule, so the amounts are too alike to call any day heavy.
double? heavyCut(List<double> totals) {
  if (totals.length < 2) return null;
  final double quartile = quantile(totals, 0.75);
  final double middle = median(totals);
  double? cut;
  for (final double total in totals) {
    if (total >= quartile && total > middle && (cut == null || total < cut)) {
      cut = total;
    }
  }
  return cut;
}

/// A measure on one night (or day) after a heavy day, against the person's
/// ordinary nights.
class RecoveryNight {
  const RecoveryNight({
    required this.effect,
    required this.interval,
    required this.pValue,
    required this.off,
    required this.back,
  });

  final double effect;
  final Interval interval;

  /// Two-sided, for [effect] being zero.
  final double pValue;

  /// The interval at [InsightGates.level] excludes zero and, once judged by
  /// [judgeRecovery], the difference stands among the report's comparisons.
  final bool off;

  /// The two one-sided tests' interval lies wholly within the measure's floor
  /// of zero: the night is shown to be back, not merely unclear.
  final bool back;

  RecoveryNight get unclear => RecoveryNight(
    effect: effect,
    interval: interval,
    pValue: pValue,
    off: false,
    back: back,
  );
}

/// One measure followed over the nights after a habit's heavy days: a finding
/// when [refusal] is null.
class Recovery {
  const Recovery({
    required this.habitId,
    required this.metricId,
    required this.usableDays,
    required this.heavyDays,
    this.cut,
    this.floor,
    this.nights = const <RecoveryNight>[],
    this.refusal,
  });

  final String habitId;
  final String metricId;

  /// The nights (or days) of the measure the model ran on.
  final int usableDays;

  /// Of [usableDays], those straight after a heavy day.
  final int heavyDays;

  /// A heavy day is one whose total is at or over this ([heavyCut]).
  final double? cut;

  /// The measure's floor for this person: the margin "back to usual" is
  /// judged within.
  final double? floor;

  /// The first [recoveryNights] nights after a heavy day, in order; empty
  /// until fitted. Once fitted, each counts in the report's family.
  final List<RecoveryNight> nights;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  /// How many nights in a row from the first the measure is clearly off, on
  /// the first night's side and not within its floor.
  int get offNights {
    int run = 0;
    for (final RecoveryNight night in nights) {
      if (!night.off ||
          night.back ||
          night.effect.sign != nights.first.effect.sign) {
        break;
      }
      run++;
    }
    return run;
  }

  /// The first night after [offNights] shown to be back within the floor;
  /// null when none of those followed is.
  int? get backBy {
    for (int k = offNights; k < nights.length; k++) {
      if (nights[k].back) return k + 1;
    }
    return null;
  }

  Recovery _with({List<RecoveryNight>? nights, RefusalReason? refusal}) =>
      Recovery(
        habitId: habitId,
        metricId: metricId,
        usableDays: usableDays,
        heavyDays: heavyDays,
        cut: cut,
        floor: floor,
        nights: nights ?? this.nights,
        refusal: refusal ?? this.refusal,
      );

  /// Night [night] (from 1) as a [HabitFinding], for the wording a finding
  /// of the other kinds gets. Only once fitted.
  HabitFinding nightFinding(int night) => HabitFinding(
    habitId: habitId,
    metricId: metricId,
    lagDays: night,
    usableDays: usableDays,
    exposedDays: heavyDays,
    raw: null,
    cut: cut,
    effect: nights[night - 1].effect,
    interval: nights[night - 1].interval,
    standardized: 0,
    pValue: nights[night - 1].pValue,
  );
}

/// For each habit not in [skip] and each of [recoveryMetrics] that [outcomes]
/// holds and [floors] has a floor for, the measure on each of the
/// [recoveryNights] nights after a heavy day of the habit against the
/// person's ordinary nights.
///
/// A heavy day is one whose total (on the day [lateDayOf] gives, so an entry
/// after midnight belongs to the evening before the night) reaches
/// [heavyCut] of the habit's own days of use. The model is one least squares
/// fit of the measure on day t on: a heavy day 1, 2 and 3 days before (the
/// three effects reported, each with the other two held fixed, so the second
/// night after a Friday is not read as the first after a Saturday); ordinary
/// use the day before, centred so the reference is the person's usual mix of
/// days with and without it; every other habit's use the day before; for a
/// measure averaged over the calendar day, a heavy day on t itself; whether
/// t is a weekend day; a trend and a level per period.
///
/// The measure's own previous value is not held fixed for the later nights:
/// it lies between the heavy day and them, and would take the carry-over
/// with it. Its day-to-day persistence goes into the errors instead: the fit
/// is generalised least squares for errors that are first-order
/// autoregressive across the days present, their correlation estimated from
/// the residuals (twice over).
///
/// That estimate runs low, and what it misses of a bad night that led to the
/// heavy day would read as the day's cost. So the first night of a measure
/// of the night itself comes from a second, ordinary least squares fit that
/// also holds the night before fixed, on the nights that have one: that
/// night ended before the heavy day began, so it can carry none of the
/// day's effect. A measure of the calendar day gets no such fit, since its
/// value on the heavy day already holds some of the cost.
///
/// The first night must be clear on its own (and not rest on one night);
/// each later night is "still off" only when its own interval excludes zero,
/// and "back" only when its interval at twice the tail lies within the floor
/// (two one-sided tests), so an unclear night is never called recovered.
List<Recovery> recoveryAfterHeavyDays({
  required List<HabitUse> uses,
  required OutcomeSeries outcomes,
  required DateTime through,
  required Map<String, double> floors,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final List<String> ids = habits.habitIds.toList()..sort();
  final Set<String> held = outcomes.metricIds.toSet();
  return <Recovery>[
    for (final String metricId in recoveryMetrics)
      if (held.contains(metricId) && floors[metricId] != null)
        for (final String id in ids)
          if (!skip.contains(id))
            _recovery(
              id,
              metricId,
              ids: ids,
              habits: habits,
              outcomes: outcomes,
              through: startOfDay(through),
              floor: floors[metricId]!,
              gates: gates,
            ),
  ];
}

// The fewest days the model must have beyond its columns.
const int _minResidualDays = 10;

// The fewest pairs of next-door days the errors' correlation is estimated
// from; with fewer the errors are taken as independent.
const int _minAdjacentPairs = 14;

Recovery _recovery(
  String id,
  String metricId, {
  required List<String> ids,
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required DateTime through,
  required double floor,
  required InsightGates gates,
}) {
  final double? cut = heavyCut(<double>[
    for (final DateTime day in habits.lateDays(id))
      habits.lateDayTotal(id, day),
  ]);
  bool heavy(DateTime day) =>
      cut != null && habits.lateDayTotal(id, day) >= cut;

  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[];
  final DateTime? first = habits.firstUse(id);
  final DateTime? last = habits.lastUse(id);
  if (first != null && last != null) {
    final DateTime end = addDays(last, 1);
    for (final DateTime day in daysFrom(
      addDays(first, 1),
      end.isBefore(through) ? end : through,
    )) {
      final double? value = outcomes.value(metricId, day);
      if (value == null) continue;
      days.add(day);
      y.add(value);
    }
  }
  final int n = days.length;
  final List<List<double>> lags = <List<double>>[
    for (int k = 1; k <= recoveryNights; k++)
      <double>[for (final DateTime d in days) heavy(addDays(d, -k)) ? 1 : 0],
  ];
  final List<double> after = lags.first;
  final int heavyDays = after.where((v) => v == 1).length;
  Recovery result({
    RefusalReason? refusal,
    List<RecoveryNight> nights = const <RecoveryNight>[],
  }) => Recovery(
    habitId: id,
    metricId: metricId,
    usableDays: n,
    heavyDays: heavyDays,
    cut: cut,
    floor: floor,
    nights: nights,
    refusal: refusal,
  );

  if (n < gates.minDays) return result(refusal: RefusalReason.tooFewDays);
  if (cut == null) return result(refusal: RefusalReason.steadyAmount);
  int clear = 0;
  for (int r = 0; r < n; r++) {
    if (lags.every((List<double> lag) => lag[r] == 0)) clear++;
  }
  if (heavyDays < gates.minExposedDays || clear < gates.minUnexposedDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  final List<int> period = periodsOf(days, gates.minPeriodDays);
  if (period.last > 0
      ? _mixedPeriods(after, period) < gates.minMixedPeriods
      : unevenHalves(after, n ~/ 2, gates)) {
    return result(refusal: RefusalReason.uneven);
  }

  // Ordinary use the day before, less its usual rate, and nothing after a
  // heavy day: the intercept is then the usual night, with or without it.
  final List<double> usedBefore = <double>[
    for (final DateTime d in days)
      habits.lateDayTotal(id, addDays(d, -1)) > 0 ? 1 : 0,
  ];
  final List<double> ordinaryRows = <double>[
    for (int r = 0; r < n; r++)
      if (after[r] == 0) usedBefore[r],
  ];
  final double usual = ordinaryRows.isEmpty ? 0 : mean(ordinaryRows);
  final List<List<double>> fixed = <List<double>>[
    <double>[
      for (int r = 0; r < n; r++) after[r] == 1 ? 0 : usedBefore[r] - usual,
    ],
    if (!sleepMinutesIds.contains(metricId))
      <double>[for (final DateTime d in days) heavy(d) ? 1 : 0],
    <double>[for (final DateTime d in days) d.weekday >= 6 ? 1 : 0],
    <double>[
      for (final DateTime d in days)
        d.difference(days.first).inHours / 24 / max(1, n),
    ],
    if (period.last == 0)
      <double>[for (int r = 0; r < n; r++) r >= n ~/ 2 ? 1 : 0]
    else
      for (int k = 1; k <= period.last; k++)
        <double>[for (final int p in period) p == k ? 1 : 0],
  ];
  final List<List<double>> others =
      <List<double>>[
        for (final String other in ids)
          if (other != id)
            <double>[
              for (final DateTime d in days)
                habits.lateDayTotal(other, addDays(d, -1)) > 0 ? 1 : 0,
            ],
      ]..removeWhere((List<double> c) {
        final int on = c.where((v) => v == 1).length;
        return on < gates.minExposedDays || n - on < gates.minUnexposedDays;
      });
  List<List<double>> rows(List<List<double>> columns) {
    final List<List<double>> kept = <List<double>>[
      for (final List<double> c in columns)
        if (sampleVariance(c) > 1e-12) c,
    ];
    return <List<double>>[
      for (int r = 0; r < n; r++)
        <double>[
          1,
          for (final List<double> lag in lags) lag[r],
          for (final List<double> c in kept) c[r],
        ],
    ];
  }

  // Two habits used on the same days give one column twice: the fit then
  // goes without the other habits.
  List<List<double>> design = rows(<List<double>>[...fixed, ...others]);
  LinearFit? plain = fitLeastSquares(design, y);
  if (plain == null) {
    design = rows(fixed);
    plain = fitLeastSquares(design, y);
  }
  if (plain == null || plain.degreesOfFreedom < _minResidualDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  if (plain.inverseGram[1][1] * (n - 1) * sampleVariance(after) >
      gates.maxVarianceInflation) {
    return result(refusal: RefusalReason.entangled);
  }

  final ({List<List<double>> rows, List<double> y, LinearFit fit}) model =
      _autoregressiveFit(design, y, days, plain);
  ({List<List<double>> rows, List<double> y, LinearFit fit}) opening = model;
  if (sleepMinutesIds.contains(metricId)) {
    final ({List<List<double>> rows, List<double> y, LinearFit fit})? given =
        _givenNightBefore(design, y, days);
    if (given == null ||
        given.fit.degreesOfFreedom < _minResidualDays ||
        given.rows.where((List<double> row) => row[1] == 1).length <
            gates.minExposedDays) {
      return result(refusal: RefusalReason.tooFewDays);
    }
    opening = given;
  }
  RecoveryNight night(LinearFit fit, int k) {
    final Interval within = fit.interval(k, level: 2 * gates.level - 1);
    return RecoveryNight(
      effect: fit.coefficients[k],
      interval: fit.interval(k, level: gates.level),
      pValue: fit.pValue(k),
      off: !fit.interval(k, level: gates.level).crossesZero,
      back: within.low > -floor && within.high < floor,
    );
  }

  final List<RecoveryNight> nights = <RecoveryNight>[
    night(opening.fit, 1),
    for (int k = 2; k <= recoveryNights; k++) night(model.fit, k),
  ];
  if (!nights.first.off) {
    return result(refusal: RefusalReason.withinNoise, nights: nights);
  }
  return result(
    refusal:
        withoutMostTelling(opening.rows, opening.y, opening.fit, 1, gates.level)
        ? RefusalReason.oneDay
        : null,
    nights: nights,
  );
}

// [design] and [y] on the rows whose day before is also a row, with that
// day's value as one more column; a column left constant on those rows is
// dropped, the intercept and the heavy-day columns apart. Null when it cannot
// be fitted.
({List<List<double>> rows, List<double> y, LinearFit fit})? _givenNightBefore(
  List<List<double>> design,
  List<double> y,
  List<DateTime> days,
) {
  final List<int> kept = <int>[
    for (int r = 1; r < y.length; r++)
      if ((days[r].difference(days[r - 1]).inHours / 24).round() == 1) r,
  ];
  if (kept.length < 2) return null;
  final List<int> columns = <int>[
    for (int j = 0; j < design.first.length; j++)
      if (j <= recoveryNights ||
          sampleVariance(<double>[for (final int r in kept) design[r][j]]) >
              1e-12)
        j,
  ];
  final List<List<double>> rows = <List<double>>[
    for (final int r in kept)
      <double>[for (final int j in columns) design[r][j], y[r - 1]],
  ];
  final List<double> ys = <double>[for (final int r in kept) y[r]];
  final LinearFit? fit = fitLeastSquares(rows, ys);
  return fit == null ? null : (rows: rows, y: ys, fit: fit);
}

int _mixedPeriods(List<double> x, List<int> period) {
  final Map<int, Set<double>> seen = <int, Set<double>>{};
  for (int r = 0; r < x.length; r++) {
    seen.putIfAbsent(period[r], () => <double>{}).add(x[r]);
  }
  return seen.values.where((Set<double> s) => s.length > 1).length;
}

// [plain] refitted for errors that follow e(t) = rho e(t - 1) + v(t): each
// row less rho^g times the row before it, g days earlier, over
// sqrt(1 - rho^2g), which leaves every row's error with one variance and no
// correlation with the last (exact for such errors, days missing or not).
// rho is the residuals' correlation over next-door days, held to 0 to 0.9: a
// negative one would narrow the intervals. Returns [plain] and the rows as
// they are when rho is 0 or there are too few next-door days to tell.
({List<List<double>> rows, List<double> y, LinearFit fit}) _autoregressiveFit(
  List<List<double>> design,
  List<double> y,
  List<DateTime> days,
  LinearFit plain,
) {
  final int n = y.length;
  final List<int> gap = <int>[
    0,
    for (int r = 1; r < n; r++)
      (days[r].difference(days[r - 1]).inHours / 24).round(),
  ];
  ({List<List<double>> rows, List<double> y, LinearFit fit}) model = (
    rows: design,
    y: y,
    fit: plain,
  );
  for (int pass = 0; pass < 2; pass++) {
    final List<double> residual = <double>[
      for (int r = 0; r < n; r++)
        () {
          double fitted = 0;
          for (int j = 0; j < design[r].length; j++) {
            fitted += design[r][j] * model.fit.coefficients[j];
          }
          return y[r] - fitted;
        }(),
    ];
    double cross = 0, before = 0, now = 0;
    int pairs = 0;
    for (int r = 1; r < n; r++) {
      if (gap[r] != 1) continue;
      cross += residual[r] * residual[r - 1];
      before += residual[r - 1] * residual[r - 1];
      now += residual[r] * residual[r];
      pairs++;
    }
    final double rho = pairs < _minAdjacentPairs || before == 0 || now == 0
        ? 0
        : (cross / sqrt(before * now)).clamp(0.0, 0.9);
    if (rho == 0) return (rows: design, y: y, fit: plain);
    final List<List<double>> rows = <List<double>>[];
    final List<double> ys = <double>[];
    for (int r = 0; r < n; r++) {
      final double w = r == 0 ? 0 : pow(rho, gap[r]).toDouble();
      final double scale = sqrt(1 - w * w);
      rows.add(<double>[
        for (int j = 0; j < design[r].length; j++)
          (design[r][j] - (r == 0 ? 0 : w * design[r - 1][j])) / scale,
      ]);
      ys.add((y[r] - (r == 0 ? 0 : w * y[r - 1])) / scale);
    }
    final LinearFit? fit = fitLeastSquares(rows, ys);
    if (fit == null) return model;
    model = (rows: rows, y: ys, fit: fit);
  }
  return model;
}

/// Every fitted night's p-value in [results], for the report's family.
List<double> recoveryPValues(List<Recovery> results) => <double>[
  for (final Recovery r in results)
    for (final RecoveryNight night in r.nights) night.pValue,
];

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside]. Every fitted night counts in the family. A
/// finding whose first night fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] is refused as [RefusalReason.chance],
/// then one whose first night is under its floor as
/// [RefusalReason.tooSmall]; a later night that fails is no longer
/// [RecoveryNight.off].
///
/// [RecoveryNight.back] stays outside the family: it claims no difference,
/// and shows only under a first night that passed.
List<Recovery> judgeRecovery(
  List<Recovery> results, {
  required List<double> alongside,
  InsightGates gates = const InsightGates(),
}) {
  final List<bool> kept = benjaminiHochberg(<double>[
    ...recoveryPValues(results),
    ...alongside,
  ], gates.falseDiscoveryRate);
  int at = 0;
  final List<Recovery> judged = <Recovery>[];
  for (final Recovery r in results) {
    final List<bool> mine = kept.sublist(at, at + r.nights.length);
    at += r.nights.length;
    if (!r.found) {
      judged.add(r);
    } else if (!mine.first) {
      judged.add(r._with(refusal: RefusalReason.chance));
    } else if (r.nights.first.effect.abs() < r.floor!) {
      judged.add(r._with(refusal: RefusalReason.tooSmall));
    } else {
      judged.add(
        r._with(
          nights: <RecoveryNight>[
            for (int k = 0; k < r.nights.length; k++)
              mine[k] ? r.nights[k] : r.nights[k].unclear,
          ],
        ),
      );
    }
  }
  return judged;
}
