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
  });

  final int minDays;
  final int minExposedDays;
  final int minUnexposedDays;
  final double maxVarianceInflation;
  final double level;
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
  });

  /// The outcome's difference after a day with the habit, holding every other
  /// habit's use that day fixed.
  final double effect;
  final Interval interval;

  /// [effect] in units of the outcome's standard deviation over the usable
  /// days.
  final double standardized;
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
  });

  final RefusalReason reason;
  final String? entangledWith;
  final double? effect;
  final Interval? interval;
}

/// For each habit, what [metricId] looks like [lagDays] days after a day it was
/// used, against days it was not.
///
/// Days run from [from] to [through], by default the journal's first and last
/// days with any use, so the days before someone started logging do not count
/// as days without. A day whose outcome is missing is left out.
///
/// Attribution: every habit with days both ways enters one least-squares model
/// of the outcome on an intercept and a 0/1 "used that day" indicator per
/// habit, so each coefficient is that habit's difference with the others held
/// fixed, and a habit that only rides along with another gets no credit.
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
  final DateTime? start = from ?? habits.firstDay;
  final DateTime? end = through ?? habits.lastDay;

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
  final Map<String, List<double>> exposure = <String, List<double>>{
    for (final String id in habitIds)
      id: <double>[
        for (final DateTime day in days) habits.total(id, day) > 0 ? 1 : 0,
      ],
  };

  Comparison? rawFor(String id) => _welch(exposure[id]!, y, gates.level);

  HabitRefusal refuse(
    String id,
    RefusalReason reason, {
    String? entangledWith,
    double? effect,
    Interval? interval,
  }) => HabitRefusal(
    habitId: id,
    metricId: metricId,
    lagDays: lagDays,
    usableDays: days.length,
    raw: rawFor(id),
    reason: reason,
    entangledWith: entangledWith,
    effect: effect,
    interval: interval,
  );

  if (days.length < gates.minDays) {
    return <HabitInsight>[
      for (final String id in habitIds) refuse(id, RefusalReason.tooFewDays),
    ];
  }

  int exposedCount(String id) => exposure[id]!.where((v) => v == 1).length;

  String? closestPartner(String id, Iterable<String> among) {
    String? best;
    double bestR = -1;
    for (final String other in among) {
      if (other == id) continue;
      final double r = correlation(exposure[id]!, exposure[other]!).abs();
      if (r > bestR) {
        bestR = r;
        best = other;
      }
    }
    return best;
  }

  // Columns join one at a time, the most used first; one that makes the
  // design singular duplicates habits already in, so it and its closest
  // partner are both entangled.
  final List<String> candidates = habitIds.where((id) {
    final int exposed = exposedCount(id);
    return exposed > 0 && exposed < days.length;
  }).toList()..sort((a, b) => exposedCount(b).compareTo(exposedCount(a)));
  final List<String> inModel = <String>[];
  final Map<String, String> entangled = <String, String>{};
  List<List<double>> design(List<String> ids) => <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[1, for (final String id in ids) exposure[id]![r]],
  ];
  for (final String id in candidates) {
    if (invert(gram(design(<String>[...inModel, id]))) == null) {
      final String partner = closestPartner(id, inModel)!;
      entangled[id] = partner;
      entangled.putIfAbsent(partner, () => id);
    } else {
      inModel.add(id);
    }
  }

  final LinearFit? fit = inModel.isEmpty
      ? null
      : fitLeastSquares(design(inModel), y);
  final double sd = sqrt(sampleVariance(y));

  return <HabitInsight>[
    for (final String id in habitIds)
      () {
        final int exposed = exposedCount(id);
        if (exposed < gates.minExposedDays ||
            days.length - exposed < gates.minUnexposedDays) {
          return refuse(id, RefusalReason.tooFewDays);
        }
        if (entangled.containsKey(id)) {
          return refuse(
            id,
            RefusalReason.entangled,
            entangledWith: entangled[id],
          );
        }
        if (fit == null) return refuse(id, RefusalReason.tooFewDays);
        final int column = inModel.indexOf(id) + 1;
        final double effect = fit.coefficients[column];
        final Interval interval = fit.interval(column, level: gates.level);
        // With an intercept in the model, (X'X)^-1 at j is
        // 1 / (SS_j (1 - R_j^2)), so this is 1 / (1 - R_j^2).
        final List<double> x = exposure[id]!;
        final double mx = mean(x);
        final double ss = x.fold<double>(0, (s, v) => s + (v - mx) * (v - mx));
        final double inflation = fit.inverseGram[column][column] * ss;
        if (inflation > gates.maxVarianceInflation) {
          return refuse(
            id,
            RefusalReason.entangled,
            entangledWith: closestPartner(id, inModel),
            effect: effect,
            interval: interval,
          );
        }
        if (interval.crossesZero) {
          return refuse(
            id,
            RefusalReason.withinNoise,
            effect: effect,
            interval: interval,
          );
        }
        return HabitFinding(
          habitId: id,
          metricId: metricId,
          lagDays: lagDays,
          usableDays: days.length,
          raw: rawFor(id),
          effect: effect,
          interval: interval,
          standardized: sd == 0 ? 0 : effect / sd,
        );
      }(),
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
