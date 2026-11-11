import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/health_source.dart'
    show HealthSample, HealthSampleMetric;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/step_changes.dart';
import 'package:tracker/insights/what_follows.dart';

// Health values stay on the device: nothing here is logged or reported.

/// What a [BeforeUse] sets a measure taken before a day, or before a use,
/// against.
enum BeforeUseKind {
  /// Days with the habit against days without it.
  whether,

  /// Among days with the habit, the day's total amount.
  amount,

  /// Among days with the habit, how early its first use comes.
  firstUse,

  /// Heart rate in the hour before a use against the same hour, as long
  /// after waking, on a nearby day clear of the habit.
  hourBefore,
}

/// The daily measures judged before a day's use, as `HealthMetric.id`.
const List<String> beforeUseMetrics = <String>[
  'sleepAsleep',
  'heartRateVariabilitySDNN',
  'restingHeartRate',
];

/// When the night's main sleep ended (`HealthMetric.sleepEnd`).
const String sleepEndId = 'sleepEnd';

/// The sample measure [hourBefore] judges.
const String hourBeforeMetricId = 'heartRate';

/// The measures keyed to the night that ends on a day; the rest are a
/// calendar day's average, which on the day itself takes in readings after
/// the use, so the day before is read instead.
bool _endsOnTheDay(String metricId) => sleepMinutesIds.contains(metricId);

/// One comparison of what came before a habit's use: a finding when
/// [refusal] is null.
class BeforeUse {
  const BeforeUse({
    required this.habitId,
    required this.metricId,
    required this.kind,
    required this.usableDays,
    required this.exposedDays,
    this.step = 1,
    this.effect,
    this.interval,
    this.pValue,
    this.spread,
    this.refusal,
    this.shortfall,
  });

  final String habitId;
  final String metricId;
  final BeforeUseKind kind;
  final int usableDays;

  /// Of [usableDays], the days with the habit: all of them for an amount or
  /// a first use.
  final int exposedDays;

  /// What [effect] is per: 1 for a use, an amount in the habit's unit, or 60
  /// minutes earlier.
  final double step;

  /// The measure's difference before a day with the habit, per [step] more
  /// of it, or per [step] minutes earlier a first use; for the hour before,
  /// against the control hours. In the measure's units.
  final double? effect;
  final Interval? interval;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;

  /// For an amount or a first use: the interquartile range of the habit's
  /// column, in its units.
  final double? spread;
  final RefusalReason? refusal;

  /// Set for [BeforeUseKind.hourBefore] refused for too few days.
  final HoursAfterShortfall? shortfall;

  bool get found => refusal == null;

  BeforeUse refused(RefusalReason reason) => BeforeUse(
    habitId: habitId,
    metricId: metricId,
    kind: kind,
    usableDays: usableDays,
    exposedDays: exposedDays,
    step: step,
    effect: effect,
    interval: interval,
    pValue: pValue,
    spread: spread,
    refusal: reason,
    shortfall: shortfall,
  );

  /// As a [HabitFinding], for the sizing and wording a finding of the other
  /// direction gets. Only for a finding.
  HabitFinding get asFinding => HabitFinding(
    habitId: habitId,
    metricId: metricId,
    lagDays: 0,
    usableDays: usableDays,
    exposedDays: exposedDays,
    raw: null,
    kind: switch (kind) {
      BeforeUseKind.whether || BeforeUseKind.hourBefore => InsightKind.use,
      BeforeUseKind.amount => InsightKind.dose,
      BeforeUseKind.firstUse => InsightKind.lastUse,
    },
    step: step,
    effect: effect!,
    interval: interval!,
    standardized: 0,
    pValue: pValue!,
    spread: spread,
  );
}

/// Per habit, the first use of each day in minutes after its midnight, a use
/// before [lateUseCutoffHour] counting as the evening before (so never as
/// the day's earliest).
Map<String, Map<DateTime, int>> firstUseMinutes(Iterable<HabitUse> uses) {
  final Map<String, Map<DateTime, int>> first = <String, Map<DateTime, int>>{};
  for (final HabitUse u in uses) {
    if (u.amount <= 0) continue;
    final DateTime day = lateDayOf(u.at);
    final int minutes =
        u.at.hour * 60 +
        u.at.minute +
        (day == startOfDay(u.at) ? 0 : Duration.minutesPerDay);
    final Map<DateTime, int> days = first.putIfAbsent(
      u.habitId,
      () => <DateTime, int>{},
    );
    days[day] = min(days[day] ?? minutes, minutes);
  }
  return first;
}

/// For each habit not in [skip] and each of [beforeUseMetrics] that
/// [outcomes] holds, the measure before a day against that day's use of the
/// habit: whether it was used, how much, and how early.
///
/// The measure before day d is the night that ended on d for sleep, and day
/// d - 1's average for the rest. It is the response of one least-squares
/// model on the days of the habit's span up to [through] (the last whole
/// day): the habit's column for day d (used or not; its amount; its first
/// use, in minutes earlier), then what must be held fixed for the measure to
/// be "before" rather than "after": the habit's own use and amount on d - 1
/// and every other habit's use on d - 1 (use comes in runs, and yesterday's
/// use moves last night's measure), the measure's own previous value, whether
/// d is a weekend day, a trend and a level per period. The test of the
/// habit's column is the same whichever of the two is the response; this
/// way round the effect is in the measure's units and takes its floor. A
/// day's use is the day [lateDayOf] gives, so an entry after midnight
/// belongs to the evening before the night.
///
/// A first use against the minutes of sleep also holds [sleepEndId] fixed:
/// a later waking is more sleep and a later first use by arithmetic.
///
/// An amount or a first use that one day decides is refused as
/// [RefusalReason.oneDay].
List<BeforeUse> beforeUse({
  required List<HabitUse> uses,
  required OutcomeSeries outcomes,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final Map<String, Map<DateTime, int>> first = firstUseMinutes(uses);
  final List<String> ids = habits.habitIds.toList()..sort();
  final Set<String> held = outcomes.metricIds.toSet();
  return <BeforeUse>[
    for (final String metricId in beforeUseMetrics)
      if (held.contains(metricId))
        for (final String id in ids)
          if (!skip.contains(id))
            for (final BeforeUseKind kind in const <BeforeUseKind>[
              BeforeUseKind.whether,
              BeforeUseKind.amount,
              BeforeUseKind.firstUse,
            ])
              _daily(
                id,
                metricId,
                kind,
                ids: ids,
                habits: habits,
                first: first[id] ?? const <DateTime, int>{},
                outcomes: outcomes,
                through: startOfDay(through),
                gates: gates,
              ),
  ];
}

BeforeUse _daily(
  String id,
  String metricId,
  BeforeUseKind kind, {
  required List<String> ids,
  required DailyHabitSeries habits,
  required Map<DateTime, int> first,
  required OutcomeSeries outcomes,
  required DateTime through,
  required InsightGates gates,
}) {
  final int back = _endsOnTheDay(metricId) ? 0 : 1;
  final bool holdWaking =
      kind == BeforeUseKind.firstUse && _endsOnTheDay(metricId);
  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[];
  final List<double> previous = <double>[];
  final List<double> x = <double>[];
  final List<double> waking = <double>[];
  final DateTime? start = habits.firstUse(id);
  final DateTime? last = habits.lastUse(id);
  if (start != null && last != null) {
    final DateTime end = last.isBefore(through) ? last : through;
    for (final DateTime day in daysFrom(start, end)) {
      final double? value = outcomes.value(metricId, addDays(day, -back));
      final double? before = outcomes.value(metricId, addDays(day, -back - 1));
      if (value == null || before == null) continue;
      final double total = habits.lateDayTotal(id, day);
      final double? column = switch (kind) {
        BeforeUseKind.whether => total > 0 ? 1 : 0,
        BeforeUseKind.amount => total > 0 ? total : null,
        _ => total > 0 ? -(first[day] ?? 0).toDouble() : null,
      };
      if (column == null) continue;
      if (holdWaking) {
        final double? woke = outcomes.value(sleepEndId, day);
        if (woke == null) continue;
        waking.add(woke);
      }
      days.add(day);
      y.add(value);
      previous.add(before);
      x.add(column);
    }
  }
  final int exposed = kind == BeforeUseKind.whether
      ? x.where((v) => v == 1).length
      : x.length;
  double step = kind == BeforeUseKind.firstUse ? 60 : 1;
  BeforeUse result({
    RefusalReason? refusal,
    double? effect,
    Interval? interval,
    double? pValue,
    double? spread,
  }) => BeforeUse(
    habitId: id,
    metricId: metricId,
    kind: kind,
    usableDays: days.length,
    exposedDays: exposed,
    step: step,
    effect: effect,
    interval: interval,
    pValue: pValue,
    spread: spread,
    refusal: refusal,
  );

  if (days.length < gates.minDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  switch (kind) {
    case BeforeUseKind.whether:
      if (exposed < gates.minExposedDays ||
          days.length - exposed < gates.minUnexposedDays) {
        return result(refusal: RefusalReason.tooFewDays);
      }
    case BeforeUseKind.amount:
      final Map<double, int> counts = <double, int>{};
      for (final double v in x) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final double sd = sqrt(sampleVariance(x));
      if (x.length - counts.values.reduce(max) < gates.minExposedDays ||
          sd < gates.minAmountSpread * mean(x)) {
        return result(refusal: RefusalReason.steadyAmount);
      }
      step = doseStep(sd, whole: x.every((v) => v == v.roundToDouble()));
    case BeforeUseKind.firstUse || BeforeUseKind.hourBefore:
      final double middle = median(x);
      if (sqrt(sampleVariance(x)) < gates.minTimingSpreadMinutes ||
          x.where((v) => (v - middle).abs() >= 60).length <
              gates.minExposedDays) {
        return result(refusal: RefusalReason.steadyTiming);
      }
  }
  final List<int> period = periodsOf(days, gates.minPeriodDays);
  if (period.last > 0) {
    if (_varyingPeriods(x, period) < gates.minMixedPeriods) {
      return result(refusal: RefusalReason.uneven);
    }
  } else if (kind == BeforeUseKind.whether &&
      unevenHalves(x, days.length ~/ 2, gates)) {
    return result(refusal: RefusalReason.uneven);
  }

  final List<double> amountsBefore = <double>[
    for (final DateTime d in days) habits.lateDayTotal(id, addDays(d, -1)),
  ];
  final List<List<double>> fixed = <List<double>>[
    previous,
    if (holdWaking) waking,
    <double>[for (final DateTime d in days) d.weekday >= 6 ? 1 : 0],
    <double>[
      for (final DateTime d in days)
        d.difference(days.first).inHours / 24 / max(1, days.length),
    ],
    if (period.last == 0)
      <double>[
        for (int r = 0; r < days.length; r++) r >= days.length ~/ 2 ? 1 : 0,
      ]
    else
      for (int k = 1; k <= period.last; k++)
        <double>[for (final int p in period) p == k ? 1 : 0],
    <double>[
      for (final DateTime d in days)
        habits.lateDayTotal(id, addDays(d, -1)) > 0 ? 1 : 0,
    ],
    if (sampleVariance(amountsBefore.where((v) => v > 0).toList()) > 1e-12)
      amountsBefore,
  ];
  final List<List<double>> others =
      <List<double>>[
        for (final String other in ids)
          if (other != id)
            <double>[
              for (final DateTime d in days)
                habits.lateDayTotal(other, addDays(d, -1)) > 0 ? 1 : 0,
            ],
      ]..removeWhere((c) {
        final int on = c.where((v) => v == 1).length;
        return on < gates.minExposedDays ||
            c.length - on < gates.minUnexposedDays;
      });
  List<List<double>> rows(List<List<double>> columns) {
    final List<List<double>> kept = <List<double>>[
      for (final List<double> c in columns)
        if (sampleVariance(c) > 1e-12) c,
    ];
    return <List<double>>[
      for (int r = 0; r < days.length; r++)
        <double>[1, x[r], for (final List<double> c in kept) c[r]],
    ];
  }

  // A shift in the measure's level is held fixed, as in what_follows.dart: one
  // with a week of these days on each side, unless it repeats a period's
  // level.
  for (final LevelShift shift in outcomes.shifts(metricId).shifts) {
    final List<double> after = <double>[
      for (final DateTime d in days)
        addDays(d, -back).isBefore(shift.at) ? 0 : 1,
    ];
    final int on = after.where((v) => v == 1).length;
    if (on >= gates.minExposedDays &&
        days.length - on >= gates.minExposedDays &&
        fitLeastSquares(rows(<List<double>>[...fixed, after]), y) != null) {
      fixed.add(after);
    }
  }
  // Two habits used on the same days give one column twice: the fit then
  // goes without the other habits.
  List<List<double>> design = rows(<List<double>>[...fixed, ...others]);
  LinearFit? fit = fitLeastSquares(design, y);
  if (fit == null) {
    design = rows(fixed);
    fit = fitLeastSquares(design, y);
  }
  if (fit == null || fit.degreesOfFreedom < _minResidualDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  final (
    fit: LinearFit widened,
    :double inflation,
    :Interval? Function(double level) bootstrap,
  ) = judgeDays(
    design,
    y,
    fit,
    1,
    days,
    gates,
  );
  fit = widened;
  final double effect = fit.coefficients[1] * step;
  final Interval raw = fit.interval(1, level: gates.level);
  final Interval interval = Interval(raw.low * step, raw.high * step);
  final double p = fit.pValue(1);
  final double? spread = kind == BeforeUseKind.whether
      ? null
      : interquartileRange(x);
  if (interval.crossesZero) {
    return result(
      refusal: RefusalReason.withinNoise,
      effect: effect,
      interval: interval,
      pValue: p,
      spread: spread,
    );
  }
  if (kind != BeforeUseKind.whether &&
      withoutMostTelling(
        design,
        y,
        fit,
        1,
        gates.level,
        inflation: inflation,
      )) {
    return result(
      refusal: RefusalReason.oneDay,
      effect: effect,
      interval: interval,
      pValue: p,
      spread: spread,
    );
  }
  final Interval? redrawn = bootstrap(gates.level);
  if (redrawn != null && redrawn.crossesZero) {
    return result(
      refusal: RefusalReason.withinNoise,
      effect: effect,
      interval: Interval(redrawn.low * step, redrawn.high * step),
      pValue: p,
      spread: spread,
    );
  }
  return result(effect: effect, interval: interval, pValue: p, spread: spread);
}

// The fewest days the model must have beyond its columns.
const int _minResidualDays = 10;

int _varyingPeriods(List<double> x, List<int> period) {
  final Map<int, Set<double>> seen = <int, Set<double>>{};
  for (int r = 0; r < x.length; r++) {
    seen.putIfAbsent(period[r], () => <double>{}).add(x[r]);
  }
  return seen.values.where((s) => s.length > 1).length;
}

/// For each habit in [plan] not in [skip], heart rate in the hour before a
/// use against the same hour, as long after waking, on its control day (see
/// [planHoursAfter]): the hour's mean per day, on an intercept, a use
/// indicator and the hour's steps a minute.
///
/// Nothing is taken off for the day's level, since a day that runs high is
/// part of what may come before a use. A moment, use or control, is left out
/// when another habit was used in the [hoursAfterClearMinutes] before it
/// (its effect would read as this habit's lead-up), when the hour holds
/// under [HoursAfterGates.minSamples] readings, or when it or the
/// [HoursAfterGates.activityLingerMinutes] before it hold a walk.
List<BeforeUse> hourBefore({
  required HoursAfterPlan plan,
  required List<HabitUse> uses,
  required Map<String, List<HealthSample>> samples,
  Set<String> skip = const <String>{},
  HoursAfterGates gates = const HoursAfterGates(),
}) {
  final List<HealthSample> readings =
      samples[hourBeforeMetricId] ?? const <HealthSample>[];
  if (readings.isEmpty) return const <BeforeUse>[];
  final List<HealthSample> steps =
      samples[HealthSampleMetric.stepCount.id] ?? const <HealthSample>[];
  int longestStep = 0;
  for (final HealthSample s in steps) {
    longestStep = max(longestStep, s.end.difference(s.start).inMinutes + 1);
  }
  final Map<String, List<DateTime>> usesOf = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount > 0) usesOf.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  for (final List<DateTime> t in usesOf.values) {
    t.sort();
  }
  final Map<String, List<HoursAfterPoint>> byHabit =
      <String, List<HoursAfterPoint>>{};
  for (final HoursAfterPoint p in plan.points) {
    byHabit.putIfAbsent(p.habitId, () => []).add(p);
  }
  final List<String> ids = <String>{
    ...byHabit.keys,
    for (final MapEntry<String, int> e in plan.useDays.entries)
      if (e.value > 0) e.key,
  }.where((id) => !skip.contains(id)).toList()..sort();
  const Duration hour = Duration(minutes: hoursAfterBaselineMinutes);
  const Duration clear = Duration(minutes: hoursAfterClearMinutes);
  const Duration bin = Duration(minutes: 10);
  final List<BeforeUse> out = <BeforeUse>[];
  for (final String id in ids) {
    // Per day and side: the sums of the hour's mean and steps, and a count.
    final Map<(DateTime, bool), List<double>> days =
        <(DateTime, bool), List<double>>{};
    final Map<(HoursAfterShortfall, bool), int> drops =
        <(HoursAfterShortfall, bool), int>{...?plan.dropped[id]};
    void drop(HoursAfterShortfall why, HoursAfterPoint p) =>
        drops[(why, p.control)] = (drops[(why, p.control)] ?? 0) + 1;
    for (final HoursAfterPoint p in byHabit[id] ?? const <HoursAfterPoint>[]) {
      final DateTime from = p.at.subtract(hour);
      if (usesOf.entries.any(
        (e) => e.key != id && anyTimeIn(e.value, p.at.subtract(clear), p.at),
      )) {
        drop(HoursAfterShortfall.otherHabit, p);
        continue;
      }
      final List<double> values = readingsIn(readings, from, p.at);
      if (values.length < gates.minSamples) {
        drop(HoursAfterShortfall.readings, p);
        continue;
      }
      bool walked = false;
      for (
        DateTime t = from.subtract(
          Duration(minutes: gates.activityLingerMinutes),
        );
        steps.isNotEmpty && !walked && t.isBefore(p.at);
        t = t.add(bin)
      ) {
        walked =
            stepsPerMinute(steps, t, t.add(bin), longestMinutes: longestStep) >
            gates.maxStepsPerMinute;
      }
      if (walked) {
        drop(HoursAfterShortfall.walk, p);
        continue;
      }
      final List<double> sums = days.putIfAbsent((
        startOfDay(p.at),
        p.control,
      ), () => <double>[0, 0, 0]);
      sums[0] += mean(values);
      sums[1] += stepsPerMinute(steps, from, p.at, longestMinutes: longestStep);
      sums[2] += 1;
    }
    out.add(
      _judgeHour(
        id,
        days.entries.toList()..sort((a, b) => a.key.$1.compareTo(b.key.$1)),
        gates,
        useDays: plan.useDays[id] ?? 0,
        drops: drops,
      ),
    );
  }
  return out;
}

BeforeUse _judgeHour(
  String id,
  List<MapEntry<(DateTime, bool), List<double>>> days,
  HoursAfterGates gates, {
  required int useDays,
  required Map<(HoursAfterShortfall, bool), int> drops,
}) {
  final List<double> y = <double>[];
  final List<double> used = <double>[];
  final List<double> steps = <double>[];
  for (final MapEntry<(DateTime, bool), List<double>> d in days) {
    y.add(d.value[0] / d.value[2]);
    steps.add(d.value[1] / d.value[2]);
    used.add(d.key.$2 ? 0 : 1);
  }
  final int exposed = used.where((v) => v == 1).length;
  BeforeUse result({
    RefusalReason? refusal,
    HoursAfterShortfall? shortfall,
    double? effect,
    Interval? interval,
    double? pValue,
  }) => BeforeUse(
    habitId: id,
    metricId: hourBeforeMetricId,
    kind: BeforeUseKind.hourBefore,
    usableDays: y.length,
    exposedDays: exposed,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: refusal,
    shortfall: shortfall,
  );
  HoursAfterShortfall worst({required bool control}) {
    HoursAfterShortfall? most;
    int count = 0;
    for (final MapEntry<(HoursAfterShortfall, bool), int> e in drops.entries) {
      if (e.key.$2 == control && e.value > count) {
        most = e.key.$1;
        count = e.value;
      }
    }
    return most ??
        (control ? HoursAfterShortfall.controls : HoursAfterShortfall.uses);
  }

  if (exposed < gates.minEventDays) {
    return result(
      refusal: RefusalReason.tooFewDays,
      shortfall: useDays < gates.minEventDays
          ? HoursAfterShortfall.uses
          : worst(control: false),
    );
  }
  if (y.length - exposed < gates.minControlDays) {
    return result(
      refusal: RefusalReason.tooFewDays,
      shortfall: worst(control: true),
    );
  }
  final bool withSteps = sampleVariance(steps) > 1e-9;
  final LinearFit? fit = fitLeastSquares(<List<double>>[
    for (int r = 0; r < y.length; r++)
      <double>[1, used[r], if (withSteps) steps[r]],
  ], y);
  if (fit == null) {
    return result(
      refusal: RefusalReason.tooFewDays,
      shortfall: HoursAfterShortfall.controls,
    );
  }
  final Interval interval = fit.interval(1, level: gates.level);
  return result(
    refusal: interval.crossesZero ? RefusalReason.withinNoise : null,
    effect: fit.coefficients[1],
    interval: interval,
    pValue: fit.pValue(1),
  );
}

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside]: a finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] over them all is refused as
/// [RefusalReason.chance], then one under [sizeOf] 1 (its outcome's floor)
/// as [RefusalReason.tooSmall].
List<BeforeUse> judgeBeforeUse(
  List<BeforeUse> results, {
  required List<double> alongside,
  required double Function(BeforeUse finding) sizeOf,
  InsightGates gates = const InsightGates(),
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
  return <BeforeUse>[
    for (int i = 0; i < results.length; i++)
      if (!results[i].found)
        results[i]
      else if (chance.contains(i))
        results[i].refused(RefusalReason.chance)
      else if (sizeOf(results[i]) < 1)
        results[i].refused(RefusalReason.tooSmall)
      else
        results[i],
  ];
}
