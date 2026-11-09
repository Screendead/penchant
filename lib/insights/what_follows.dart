import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';

/// When a result is reported rather than refused. The defaults are the idea
/// file's (`ideas/insights/insights-engine.md`), not tuned on data, except
/// the four for balance, checked against synthetic habits in
/// `tools/insights-calibration/`: evenly used ones, whether used on
/// independent days or in runs of days, are refused at most about 1% of the
/// time.
class InsightGates {
  const InsightGates({
    this.minDays = 21,
    this.minExposedDays = 7,
    this.minUnexposedDays = 7,
    this.maxVarianceInflation = 5,
    this.minPeriodDays = 10,
    this.minMixedPeriods = 2,
    this.maxUseRateRatio = 3,
    this.unevenSignificance = 0.01,
    this.level = 0.95,
    this.falseDiscoveryRate = 0.1,
  });

  final int minDays;
  final int minExposedDays;
  final int minUnexposedDays;
  final double maxVarianceInflation;

  /// The fewest usable days a calendar month needs to be a period of its own.
  final int minPeriodDays;

  /// When a span holds more than one period, how many of them need days
  /// both with the habit and without it.
  final int minMixedPeriods;

  /// When a span is one period: how many times more often a habit may be
  /// used, or gone without, in one half of its span than in the other, unless
  /// the difference is within [unevenSignificance] of chance.
  final double maxUseRateRatio;
  final double unevenSignificance;
  final double level;

  /// Benjamini-Hochberg's q across every comparison in one report.
  final double falseDiscoveryRate;
}

/// The outcome after days a habit was used against after days it was not,
/// with no other habit taken into account.
class Comparison {
  const Comparison({
    required this.exposedMean,
    required this.unexposedMean,
    required this.exposedDays,
    required this.unexposedDays,
    required this.interval,
  });

  final double exposedMean;
  final double unexposedMean;
  final int exposedDays;
  final int unexposedDays;

  /// A Welch interval for [difference].
  final Interval interval;

  double get difference => exposedMean - unexposedMean;
}

enum RefusalReason {
  /// Too few usable days, or too few days with or without the habit;
  /// [HabitInsight.exposedDays] says which.
  tooFewDays,

  /// Used far more in one half of a one-period span than in the other, in
  /// too few periods both with and without it, or so much in step with the
  /// time terms that the model cannot tell it from a drift or a change in the
  /// outcome over the same months.
  uneven,

  /// Used on so many of the same days as [HabitRefusal.entangledWith] that the
  /// two cannot be told apart.
  entangled,

  /// The adjusted interval includes zero.
  withinNoise,

  /// The adjusted interval excludes zero, but not by enough to stand out
  /// among every comparison in the report. Set by the report, never by
  /// [whatFollows].
  chance,
}

sealed class HabitInsight {
  const HabitInsight({
    required this.habitId,
    required this.metricId,
    required this.lagDays,
    required this.usableDays,
    required this.exposedDays,
    required this.raw,
  });

  final String habitId;
  final String metricId;
  final int lagDays;
  final int usableDays;

  /// Of [usableDays], the days the habit was used.
  final int exposedDays;

  /// Null when either side has fewer than two days.
  final Comparison? raw;
}

class HabitFinding extends HabitInsight {
  const HabitFinding({
    required super.habitId,
    required super.metricId,
    required super.lagDays,
    required super.usableDays,
    required super.exposedDays,
    required super.raw,
    required this.effect,
    required this.interval,
    required this.standardized,
    required this.pValue,
  });

  /// The outcome's difference after a day with the habit, holding every other
  /// habit's use that day fixed.
  final double effect;
  final Interval interval;

  /// [effect] in units of the outcome's standard deviation over the usable
  /// days.
  final double standardized;

  /// Two-sided, for [effect] being zero.
  final double pValue;
}

class HabitRefusal extends HabitInsight {
  const HabitRefusal({
    required super.habitId,
    required super.metricId,
    required super.lagDays,
    required super.usableDays,
    required super.exposedDays,
    required super.raw,
    required this.reason,
    this.entangledWith,
    this.effect,
    this.interval,
    this.pValue,
  });

  final RefusalReason reason;
  final String? entangledWith;
  final double? effect;
  final Interval? interval;

  /// Set with [effect]: the habit was fitted, so it counts among the
  /// report's comparisons.
  final double? pValue;
}

/// For each habit, what [metricId] looks like [lagDays] days after a day it was
/// used, against days it was not.
///
/// Each habit is judged over its own span, the days from its first use to its
/// last, clipped to [from] and [through] when given: the days before someone
/// started logging it, or after they stopped, are not days without it. A day
/// whose outcome is missing is left out. [HabitInsight.usableDays] counts the
/// days left in that habit's span.
///
/// Attribution: on those days, one least-squares model of the outcome on an
/// intercept, a linear trend over the span, a level for each period after the
/// first, and a 0/1 "used that day" indicator for the habit and for every
/// other habit that clears the sample gates there, so the coefficient is the
/// habit's difference with the others and the time held fixed, and a habit
/// that only rides along with another, or with a drift or a step in the
/// outcome, gets no credit. A period is a calendar month, merged into its
/// neighbour while it holds fewer than [InsightGates.minPeriodDays] usable
/// days; a span of one period gets a level for its second half instead. With
/// period levels, the habit's coefficient comes from days with and without it
/// within the same period, so a change in use between months, a cut-down or
/// faded logging, is not read as an effect. A change in use and in the
/// outcome within one month still can be.
/// Another habit counts as not used on the days outside its own span: that can
/// make its coefficient a proxy for time, but its coefficient is never the one
/// reported here.
///
/// Balance: a span of several periods in which fewer than
/// [InsightGates.minMixedPeriods] hold days both with and without the habit is
/// refused, since its coefficient would rest on a single month. A span of one
/// period (a month and fewer than [InsightGates.minPeriodDays] usable days
/// beside it) has no month to compare within, so a habit used, or gone without,
/// [InsightGates.maxUseRateRatio] times more often in one half of it than the
/// other is refused: once logging fades, the days between stray entries read as
/// days without it, and a change in the outcome over them would be pinned on
/// it. That guard sees only when the habit was logged, so it also refuses a
/// real, steep change in use.
///
/// Each result is judged alone, at [InsightGates.level]; across many habits
/// and outcomes some will clear it by chance, so a report runs every result
/// through [controlFalseDiscoveries].
List<HabitInsight> whatFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _whatFollowsOne(
        id,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
      ),
  ];
}

HabitInsight _whatFollowsOne(
  String id, {
  required List<String> habitIds,
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  required int lagDays,
  required DateTime? from,
  required DateTime? through,
  required InsightGates gates,
}) {
  final DateTime? first = habits.firstUse(id), last = habits.lastUse(id);
  final DateTime? start = first == null || from == null || first.isAfter(from)
      ? first
      : startOfDay(from);
  final DateTime? end =
      last == null || through == null || last.isBefore(through)
      ? last
      : through;

  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[];
  if (start != null && end != null) {
    for (final DateTime day in daysFrom(start, end)) {
      final double? value = outcomes.value(metricId, addDays(day, lagDays));
      if (value != null) {
        days.add(day);
        y.add(value);
      }
    }
  }
  List<double> exposureOf(String habit) => <double>[
    for (final DateTime day in days) habits.total(habit, day) > 0 ? 1 : 0,
  ];
  bool clearsSampleGates(List<double> x) {
    final int exposed = x.where((v) => v == 1).length;
    return exposed >= gates.minExposedDays &&
        x.length - exposed >= gates.minUnexposedDays;
  }

  final List<double> x = exposureOf(id);
  final int exposed = x.where((v) => v == 1).length;
  final Comparison? raw = _welch(x, y, gates.level);

  HabitRefusal refuse(
    RefusalReason reason, {
    String? entangledWith,
    double? effect,
    Interval? interval,
    double? pValue,
  }) => HabitRefusal(
    habitId: id,
    metricId: metricId,
    lagDays: lagDays,
    usableDays: days.length,
    exposedDays: exposed,
    raw: raw,
    reason: reason,
    entangledWith: entangledWith,
    effect: effect,
    interval: interval,
    pValue: pValue,
  );

  if (days.length < gates.minDays || !clearsSampleGates(x)) {
    return refuse(RefusalReason.tooFewDays);
  }

  final List<int> period = _periods(days, gates.minPeriodDays);
  final int periods = period.last + 1;
  // Halves by usable days, so each holds at least half of minDays.
  final int half = days.length ~/ 2;
  if (periods == 1
      ? _unevenHalves(x, half, gates)
      : _mixedPeriods(x, period) < gates.minMixedPeriods) {
    return refuse(RefusalReason.uneven);
  }
  final int span = daysBetween(days.first, days.last);
  final List<List<double>> time = <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[
        daysBetween(days.first, days[r]) / span - 0.5,
        if (periods == 1)
          r < half ? 0 : 1
        else
          for (int k = 1; k < periods; k++) period[r] == k ? 1 : 0,
      ],
  ];
  final int timeColumns = time.first.length;

  // A habit refused for its sample never enters: a one-off use would absorb
  // its day, cost a degree of freedom and inflate this habit's variance.
  final Map<String, List<double>> others = <String, List<double>>{
    for (final String other in habitIds)
      if (other != id) other: exposureOf(other),
  }..removeWhere((_, v) => !clearsSampleGates(v));
  int exposedCount(String other) => others[other]!.where((v) => v == 1).length;
  final List<String> covariates = others.keys.toList()
    ..sort((a, b) {
      final int byUse = exposedCount(b).compareTo(exposedCount(a));
      return byUse != 0 ? byUse : a.compareTo(b);
    });

  String? closestPartner(Iterable<String> among) {
    String? best;
    double bestR = -1;
    for (final String other in among) {
      final double r = correlation(x, others[other]!).abs();
      if (r > bestR) {
        bestR = r;
        best = other;
      }
    }
    return best;
  }

  List<List<double>> design(List<String> ids) => <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[
        1,
        x[r],
        ...time[r],
        for (final String other in ids) others[other]![r],
      ],
  ];

  // With an intercept in the model, (X'X)^-1 at j is 1 / (SS_j (1 - R_j^2)),
  // so this is 1 / (1 - R_j^2).
  final double mx = mean(x);
  final double ss = x.fold<double>(0, (s, v) => s + (v - mx) * (v - mx));
  double inflationIn(List<List<double>> rows) =>
      (invert(gram(rows))?[1][1] ?? double.infinity) * ss;
  if (inflationIn(design(const <String>[])) > gates.maxVarianceInflation) {
    return refuse(RefusalReason.uneven);
  }

  // Covariates join the most used first. One that duplicates those already in
  // changes nothing this habit's coefficient can see, so it is skipped; one
  // more column than would leave a residual degree of freedom is skipped too.
  final List<String> inModel = <String>[];
  for (final String other in covariates) {
    if (inModel.length + timeColumns + 4 > days.length) break;
    final List<List<double>> without = <List<double>>[
      for (final List<double> row in design(<String>[...inModel, other]))
        <double>[row[0], ...row.skip(2)],
    ];
    if (invert(gram(without)) != null) inModel.add(other);
  }
  if (invert(gram(design(inModel))) == null) {
    return refuse(
      RefusalReason.entangled,
      entangledWith: closestPartner(covariates),
    );
  }

  final LinearFit? fit = fitLeastSquares(design(inModel), y);
  if (fit == null) return refuse(RefusalReason.tooFewDays);
  const int column = 1;
  final double effect = fit.coefficients[column];
  final Interval interval = fit.interval(column, level: gates.level);
  final double pValue = fit.pValue(column);
  final double inflation = fit.inverseGram[column][column] * ss;
  if (inflation > gates.maxVarianceInflation) {
    return refuse(
      RefusalReason.entangled,
      entangledWith: closestPartner(inModel),
      effect: effect,
      interval: interval,
      pValue: pValue,
    );
  }
  if (interval.crossesZero) {
    return refuse(
      RefusalReason.withinNoise,
      effect: effect,
      interval: interval,
      pValue: pValue,
    );
  }
  final double sd = sqrt(sampleVariance(y));
  return HabitFinding(
    habitId: id,
    metricId: metricId,
    lagDays: lagDays,
    usableDays: days.length,
    exposedDays: exposed,
    raw: raw,
    effect: effect,
    interval: interval,
    standardized: sd == 0 ? 0 : effect / sd,
    pValue: pValue,
  );
}

/// [insights] with every finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] refused as [RefusalReason.chance]. The
/// family is every result with a p-value, so a fitted habit refused for its
/// entanglement or its noise still counts as a comparison made.
List<HabitInsight> controlFalseDiscoveries(
  List<HabitInsight> insights, {
  InsightGates gates = const InsightGates(),
}) {
  double? pValueOf(HabitInsight insight) => switch (insight) {
    HabitFinding(:final double pValue) => pValue,
    HabitRefusal(:final double? pValue) => pValue,
  };
  final List<int> tested = <int>[
    for (int i = 0; i < insights.length; i++)
      if (pValueOf(insights[i]) != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) pValueOf(insights[i])!,
  ], gates.falseDiscoveryRate);
  final Set<int> rejected = <int>{
    for (int k = 0; k < tested.length; k++)
      if (!kept[k]) tested[k],
  };
  return <HabitInsight>[
    for (int i = 0; i < insights.length; i++)
      switch (insights[i]) {
        final HabitFinding f when rejected.contains(i) => HabitRefusal(
          habitId: f.habitId,
          metricId: f.metricId,
          lagDays: f.lagDays,
          usableDays: f.usableDays,
          exposedDays: f.exposedDays,
          raw: f.raw,
          reason: RefusalReason.chance,
          effect: f.effect,
          interval: f.interval,
          pValue: f.pValue,
        ),
        final HabitInsight other => other,
      },
  ];
}

// Which period each of [days] falls in, numbered from 0: one per calendar
// month, a month with fewer than [minDays] usable days merged into the next,
// and a short last one into the one before.
List<int> _periods(List<DateTime> days, int minDays) {
  final List<int> period = List<int>.filled(days.length, 0);
  int current = 0, inCurrent = 0, monthStart = 0;
  for (int r = 0; r <= days.length; r++) {
    final bool monthEnds =
        r == days.length ||
        (r > 0 &&
            (days[r].month != days[r - 1].month ||
                days[r].year != days[r - 1].year));
    if (monthEnds) {
      final int monthDays = r - monthStart;
      if (inCurrent >= minDays) {
        current++;
        inCurrent = 0;
      }
      for (int i = monthStart; i < r; i++) {
        period[i] = current;
      }
      inCurrent += monthDays;
      monthStart = r;
    }
  }
  if (inCurrent < minDays && current > 0) {
    for (int i = 0; i < days.length; i++) {
      if (period[i] == current) period[i] = current - 1;
    }
  }
  return period;
}

// Periods with days both with and without the habit, the only days its
// coefficient learns from once the period levels are in.
int _mixedPeriods(List<double> x, List<int> period) {
  final int periods = period.last + 1;
  final List<int> on = List<int>.filled(periods, 0);
  final List<int> all = List<int>.filled(periods, 0);
  for (int r = 0; r < x.length; r++) {
    all[period[r]]++;
    if (x[r] == 1) on[period[r]]++;
  }
  int mixed = 0;
  for (int k = 0; k < periods; k++) {
    if (on[k] > 0 && on[k] < all[k]) mixed++;
  }
  return mixed;
}

// The ratio alone would refuse a rare habit's chance clumping in a short
// span; the test alone would refuse a mild drift in a long one, which the time
// terms absorb. The ratio is checked on the days without the habit too: early
// days left unlogged by a daily habit read as days without it, the mirror of
// logging that fades. Days of use come in runs (a bad week, a trip), which
// makes the halves' rates differ more than independent days would, so the
// standard error is widened by the runs' lag-1 autocorrelation within each
// half.
bool _unevenHalves(List<double> x, int half, InsightGates gates) {
  final List<double> a = x.sublist(0, half), b = x.sublist(half);
  final double ra = mean(a), rb = mean(b);
  bool lopsided(double p, double q) =>
      max(p, q) > gates.maxUseRateRatio * min(p, q);
  if (!lopsided(ra, rb) && !lopsided(1 - ra, 1 - rb)) return false;
  final double pooled =
      ((a.length - 1) * sampleVariance(a) +
          (b.length - 1) * sampleVariance(b)) /
      (x.length - 2);
  final double rho = _withinHalvesAutocorrelation(a, b);
  final double se = sqrt(
    pooled * (1 / a.length + 1 / b.length) * (1 + rho) / (1 - rho),
  );
  final double p = se == 0
      ? 0
      : studentTTwoSided((ra - rb) / se, (x.length - 2).toDouble());
  return p < gates.unevenSignificance;
}

// Clamped to [0, 0.9]: a negative value would narrow the interval, and one
// near 1 leaves no evidence at all.
double _withinHalvesAutocorrelation(List<double> a, List<double> b) {
  double lagged = 0, squares = 0;
  for (final List<double> part in <List<double>>[a, b]) {
    final double m = mean(part);
    for (int i = 0; i < part.length; i++) {
      squares += (part[i] - m) * (part[i] - m);
      if (i > 0) lagged += (part[i] - m) * (part[i - 1] - m);
    }
  }
  return squares == 0 ? 0 : (lagged / squares).clamp(0.0, 0.9);
}

Comparison? _welch(List<double> exposure, List<double> y, double level) {
  final List<double> on = <double>[], off = <double>[];
  for (int i = 0; i < y.length; i++) {
    (exposure[i] == 1 ? on : off).add(y[i]);
  }
  if (on.length < 2 || off.length < 2) return null;
  final double a = sampleVariance(on) / on.length;
  final double b = sampleVariance(off) / off.length;
  final double se = sqrt(a + b);
  final double df = a + b == 0
      ? (on.length + off.length - 2).toDouble()
      : (a + b) *
            (a + b) /
            (a * a / (on.length - 1) + b * b / (off.length - 1));
  final double difference = mean(on) - mean(off);
  final double half = studentTQuantile(1 - (1 - level) / 2, df) * se;
  return Comparison(
    exposedMean: mean(on),
    unexposedMean: mean(off),
    exposedDays: on.length,
    unexposedDays: off.length,
    interval: Interval(difference - half, difference + half),
  );
}
