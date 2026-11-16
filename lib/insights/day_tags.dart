import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/calendar_days.dart' show varyingPeriods;
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';

/// The tags of one day's note: the local day it is about and its triggers as
/// stored. A locked note has none.
typedef DayTags = ({DateTime day, List<String> triggers});

/// The smallest difference in a day's total, as a share of the total on the
/// other tagged days, worth showing: [triggerFloor], as for entries.
const double dayTagFloor = triggerFloor;

// The fewest days the model must have beyond its columns, as for calendar
// days.
const int _minResidualDays = 10;

/// A habit's day total on days whose note holds [tag] against its day total
/// on the other days with a tagged note: a finding when [refusal] is null.
class DayTagAmount {
  const DayTagAmount({
    required this.tag,
    required this.withDays,
    required this.withoutDays,
    required this.withMean,
    required this.withoutMean,
    this.effect,
    this.pValue,
    this.refusal,
  });

  /// A trigger tree path, a top-level node's id alone for the whole area, or
  /// a free-text label as written.
  final String tag;
  final int withDays;
  final int withoutDays;

  /// The mean day total on each side, nothing held fixed: what the card
  /// shows.
  final double withMean;
  final double withoutMean;

  /// The difference with the habit's weekday pattern, trend, period and the
  /// day before held fixed; null when the gates left nothing to fit.
  final double? effect;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  DayTagAmount refused(RefusalReason reason) => DayTagAmount(
    tag: tag,
    withDays: withDays,
    withoutDays: withoutDays,
    withMean: withMean,
    withoutMean: withoutMean,
    effect: effect,
    pValue: pValue,
    refusal: reason,
  );
}

/// One habit's tagged days and each day tag compared on them.
class HabitDayTags {
  const HabitDayTags({
    required this.habitId,
    required this.days,
    required this.tagged,
    required this.tags,
  });

  final String habitId;

  /// Days from the habit's first entry to its last, through the last whole
  /// day.
  final int days;

  /// Those of [days] with a note holding at least one tag.
  final int tagged;

  /// Most days first.
  final List<DayTagAmount> tags;
}

/// For each habit in [uses] not in [skip] and each tag on its tagged days,
/// the habit's day total on days tagged with it against the other tagged
/// days. Unjudged: pass the result to [judgeDayTags].
///
/// Tagging a day is optional, so only days with a tagged note are compared:
/// an untagged day says nothing about what went on. A day with no entry of
/// the habit counts as 0. The rows are the tagged days of the habit's span,
/// up to [through] (the last whole day); each day's total is
/// [DailyHabitSeries.lateDayTotal], so a 01:00 entry counts to the evening
/// before, as the note about that evening would. Held fixed beside the tag:
/// the habit's usual total on that weekday over its whole span (a tag kept
/// for Fridays would otherwise take the credit for Friday's drinking), a
/// trend, a level per period and the day before's total (use comes in runs,
/// and so may a tag). A tag counts under its tree path, its top-level area,
/// or as its free-text label, as entry triggers do; an area covering the same
/// days as one path under it is left out, being the same comparison.
List<HabitDayTags> dayTagAmounts({
  required List<HabitUse> uses,
  required List<DayTags> tags,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<DateTime, Set<String>> keysOf = <DateTime, Set<String>>{
    for (final DayTags t in tags)
      if (!startOfDay(t.day).isAfter(last))
        if (<String>{for (final String s in t.triggers) ...triggerKeys(s)}
            case final Set<String> keys when keys.isNotEmpty)
          startOfDay(t.day): keys,
  };
  if (keysOf.isEmpty) return const <HabitDayTags>[];
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final List<String> ids =
      habits.habitIds.where((id) => !skip.contains(id)).toList()..sort();
  return <HabitDayTags>[
    for (final String id in ids)
      if (_habit(id, habits, keysOf, last, gates) case final HabitDayTags h) h,
  ];
}

HabitDayTags? _habit(
  String id,
  DailyHabitSeries habits,
  Map<DateTime, Set<String>> keysOf,
  DateTime through,
  InsightGates gates,
) {
  final DateTime? start = habits.firstUse(id);
  final DateTime? lastUse = habits.lastUse(id);
  if (start == null || lastUse == null || start.isAfter(through)) return null;
  final DateTime end = lastUse.isBefore(through) ? lastUse : through;
  final List<DateTime> span = daysFrom(start, end).toList();
  final List<DateTime> days = <DateTime>[
    for (final DateTime d in span)
      if (keysOf.containsKey(d)) d,
  ];
  if (days.isEmpty) return null;
  final List<double> sums = List<double>.filled(8, 0);
  final List<int> counts = List<int>.filled(8, 0);
  for (final DateTime d in span) {
    sums[d.weekday] += habits.lateDayTotal(id, d);
    counts[d.weekday]++;
  }
  final _Rows rows = (
    days: days,
    y: <double>[for (final DateTime d in days) habits.lateDayTotal(id, d)],
    weekday: <double>[
      for (final DateTime d in days) sums[d.weekday] / counts[d.weekday],
    ],
    dayBefore: <double>[
      for (final DateTime d in days) habits.lateDayTotal(id, addDays(d, -1)),
    ],
  );
  final Map<String, Set<int>> holders = <String, Set<int>>{};
  for (final (int i, DateTime d) in days.indexed) {
    for (final String k in keysOf[d]!) {
      holders.putIfAbsent(k, () => <int>{}).add(i);
    }
  }
  final List<DayTagAmount> amounts = <DayTagAmount>[
    for (final MapEntry<String, Set<int>> h in holders.entries)
      if (!sameAsChildTrigger(h.key, holders))
        _judge(h.key, h.value, rows, gates),
  ];
  amounts.sort((a, b) {
    final int byDays = b.withDays.compareTo(a.withDays);
    return byDays != 0 ? byDays : a.tag.compareTo(b.tag);
  });
  return HabitDayTags(
    habitId: id,
    days: span.length,
    tagged: days.length,
    tags: amounts,
  );
}

typedef _Rows = ({
  List<DateTime> days,
  List<double> y,
  List<double> weekday,
  List<double> dayBefore,
});

DayTagAmount _judge(String tag, Set<int> holding, _Rows rows, InsightGates g) {
  final List<DateTime> days = rows.days;
  final List<double> y = rows.y;
  final List<double> x = <double>[
    for (int r = 0; r < days.length; r++) holding.contains(r) ? 1 : 0,
  ];
  final List<double> withY = <double>[
    for (int r = 0; r < days.length; r++)
      if (x[r] == 1) y[r],
  ];
  final List<double> withoutY = <double>[
    for (int r = 0; r < days.length; r++)
      if (x[r] == 0) y[r],
  ];
  DayTagAmount result({RefusalReason? refusal, double? effect, double? p}) =>
      DayTagAmount(
        tag: tag,
        withDays: withY.length,
        withoutDays: withoutY.length,
        withMean: withY.isEmpty ? 0 : mean(withY),
        withoutMean: withoutY.isEmpty ? 0 : mean(withoutY),
        effect: effect,
        pValue: p,
        refusal: refusal,
      );

  if (withY.length < g.minExposedDays || withoutY.length < g.minUnexposedDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  if (sampleVariance(y) < 1e-12) {
    return result(refusal: RefusalReason.steadyAmount);
  }
  final List<int> period = periodsOf(days, g.minPeriodDays);
  if (period.last > 0 && varyingPeriods(x, period) < g.minMixedPeriods) {
    return result(refusal: RefusalReason.uneven);
  }
  final List<List<double>> fixed = <List<double>>[
    rows.weekday,
    <double>[
      for (final DateTime d in days)
        daysBetween(days.first, d) / max(1, daysBetween(days.first, days.last)),
    ],
    if (period.last == 0)
      <double>[
        for (int r = 0; r < days.length; r++) r >= days.length ~/ 2 ? 1 : 0,
      ]
    else
      for (int k = 1; k <= period.last; k++)
        <double>[for (final int p in period) p == k ? 1 : 0],
    rows.dayBefore,
  ];
  final List<List<double>> design = <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[
        1,
        x[r],
        for (final List<double> c in fixed)
          if (sampleVariance(c) > 1e-12) c[r],
      ],
  ];
  LinearFit? fit = fitLeastSquares(design, y);
  if (fit == null || fit.degreesOfFreedom < _minResidualDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  final (
    fit: LinearFit widened,
    inflation: _,
    :Interval? Function(double level) bootstrap,
  ) = judgeDays(
    design,
    y,
    fit,
    1,
    days,
    g,
  );
  fit = widened;
  final double effect = fit.coefficients[1];
  final double p = fit.pValue(1);
  if (fit.interval(1, level: g.level).crossesZero) {
    return result(refusal: RefusalReason.withinNoise, effect: effect, p: p);
  }
  if (bootstrap(g.level) case final Interval redrawn when redrawn.crossesZero) {
    return result(refusal: RefusalReason.withinNoise, effect: effect, p: p);
  }
  return result(effect: effect, p: p);
}

double _share(double difference, double base) => base == 0
    ? (difference == 0 ? 0 : difference.sign * double.infinity)
    : difference / base;

/// [habits] judged as part of one family with the comparisons whose
/// p-values are [alongside]: a finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] over them all is refused as
/// [RefusalReason.chance], then one under [dayTagFloor] as
/// [RefusalReason.tooSmall]. The floor reads both the difference held fixed
/// and the one the card shows, in the direction found, so a card never shows
/// a difference smaller than the floor or the other way round.
List<HabitDayTags> judgeDayTags(
  List<HabitDayTags> habits, {
  required List<double> alongside,
  InsightGates gates = const InsightGates(),
}) {
  final List<double> ps = dayTagPValues(habits);
  final List<bool> kept = benjaminiHochberg(<double>[
    ...ps,
    ...alongside,
  ], gates.falseDiscoveryRate);
  int k = 0;
  DayTagAmount judged(DayTagAmount t) {
    if (t.pValue == null) return t;
    final bool pass = kept[k++];
    if (!t.found) return t;
    if (!pass) return t.refused(RefusalReason.chance);
    final double sign = t.effect!.sign;
    final double held = _share(t.effect!, t.withoutMean).abs();
    final double shown =
        _share(t.withMean - t.withoutMean, t.withoutMean) * sign;
    return min(held, shown) < dayTagFloor
        ? t.refused(RefusalReason.tooSmall)
        : t;
  }

  return <HabitDayTags>[
    for (final HabitDayTags h in habits)
      HabitDayTags(
        habitId: h.habitId,
        days: h.days,
        tagged: h.tagged,
        tags: <DayTagAmount>[for (final DayTagAmount t in h.tags) judged(t)],
      ),
  ];
}

/// The p-values [judgeDayTags] tests, for the page's family.
List<double> dayTagPValues(List<HabitDayTags> habits) => <double>[
  for (final HabitDayTags h in habits)
    for (final DayTagAmount t in h.tags) ?t.pValue,
];
