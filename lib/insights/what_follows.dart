import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';

/// When a result is reported rather than refused. The defaults are the idea
/// file's (`ideas/insights/insights-engine.md`), not tuned on data.
class InsightGates {
  const InsightGates({
    this.minDays = 21,
    this.minExposedDays = 7,
    this.minUnexposedDays = 7,
    this.maxVarianceInflation = 5,
    this.level = 0.95,
    this.falseDiscoveryRate = 0.1,
  });

  final int minDays;
  final int minExposedDays;
  final int minUnexposedDays;
  final double maxVarianceInflation;
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
  /// Too few usable days, or too few days with or without the habit.
  tooFewDays,

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
    required this.raw,
  });

  final String habitId;
  final String metricId;
  final int lagDays;
  final int usableDays;

  /// Null when either side has fewer than two days.
  final Comparison? raw;
}

class HabitFinding extends HabitInsight {
  const HabitFinding({
    required super.habitId,
    required super.metricId,
    required super.lagDays,
    required super.usableDays,
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
/// intercept and a 0/1 "used that day" indicator for the habit and for every
/// other habit that clears the sample gates there, so the coefficient is the
/// habit's difference with the others held fixed, and a habit that only rides
/// along with another gets no credit. Another habit counts as not used on the
/// days outside its own span: that can make its coefficient a proxy for time,
/// but its coefficient is never the one reported here.
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
      <double>[1, x[r], for (final String other in ids) others[other]![r]],
  ];

  // Covariates join the most used first. One that duplicates those already in
  // changes nothing this habit's coefficient can see, so it is skipped; one
  // more column than would leave a residual degree of freedom is skipped too.
  final List<String> inModel = <String>[];
  for (final String other in covariates) {
    if (inModel.length + 4 > days.length) break;
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
  // With an intercept in the model, (X'X)^-1 at j is 1 / (SS_j (1 - R_j^2)),
  // so this is 1 / (1 - R_j^2).
  final double mx = mean(x);
  final double ss = x.fold<double>(0, (s, v) => s + (v - mx) * (v - mx));
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
