import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Calendar events stay on the device: nothing here is logged or reported.

/// A day's measure of the calendar, from its timed events of at least
/// [afterEventMinEventMinutes] that start on it.
enum CalendarDayFeature {
  /// Minutes in events, overlaps counted once, to the day's end.
  meetingMinutes,

  /// How many events.
  events,

  /// Runs of two or more events, each under [afterEventJoinMinutes] after
  /// the one before.
  backToBack,

  /// Events listing at least [calendarCrowdedAttendees] people.
  crowded,

  /// Events over [calendarLongMinutes].
  long,
}

/// An event listing this many people or more is a crowded one.
const int calendarCrowdedAttendees = 5;

/// An event longer than this many minutes is a long one.
const int calendarLongMinutes = 45;

/// The fewest days above 0 a feature needs before any habit is set against
/// it: under it, its comparisons could find nothing and would only enlarge
/// the false-discovery family.
const int calendarDayMinDays = 14;

/// The smallest difference in the share of days with a use worth showing.
const double calendarDayFloor = 0.10;

// The fewest days the model must have beyond its columns.
const int _minResidualDays = 10;

/// Each feature's value on each day from the first day with an event through
/// [through], 0 on a day without one.
Map<CalendarDayFeature, Map<DateTime, double>> calendarDayValues(
  List<CalendarEvent> events, {
  required DateTime through,
}) {
  final List<CalendarEvent> timed =
      events
          .where(
            (e) =>
                e.end.difference(e.start).inMinutes >=
                afterEventMinEventMinutes,
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final Map<CalendarDayFeature, Map<DateTime, double>> values =
      <CalendarDayFeature, Map<DateTime, double>>{
        for (final CalendarDayFeature f in CalendarDayFeature.values)
          f: <DateTime, double>{},
      };
  final DateTime last = startOfDay(through);
  if (timed.isEmpty || startOfDay(timed.first.start).isAfter(last)) {
    return values;
  }
  for (final DateTime day in daysFrom(startOfDay(timed.first.start), last)) {
    for (final Map<DateTime, double> v in values.values) {
      v[day] = 0;
    }
  }
  void add(CalendarDayFeature f, DateTime day, double by) {
    final Map<DateTime, double> v = values[f]!;
    if (v.containsKey(day)) v[day] = v[day]! + by;
  }

  const Duration join = Duration(minutes: afterEventJoinMinutes);
  DateTime? coveredTo, blockEnd;
  int inBlock = 0;
  DateTime? blockDay;
  for (final CalendarEvent e in timed) {
    final DateTime day = startOfDay(e.start);
    final DateTime dayEnd = addDays(day, 1);
    final DateTime end = e.end.isAfter(dayEnd) ? dayEnd : e.end;
    add(CalendarDayFeature.events, day, 1);
    if (e.end.difference(e.start).inMinutes > calendarLongMinutes) {
      add(CalendarDayFeature.long, day, 1);
    }
    if (e.attendees >= calendarCrowdedAttendees) {
      add(CalendarDayFeature.crowded, day, 1);
    }
    final DateTime from = coveredTo != null && coveredTo.isAfter(e.start)
        ? coveredTo
        : e.start;
    if (end.isAfter(from)) {
      add(
        CalendarDayFeature.meetingMinutes,
        day,
        end.difference(from).inSeconds / 60,
      );
      coveredTo = end;
    }
    if (blockDay == day &&
        blockEnd != null &&
        !e.start.isAfter(blockEnd.add(join))) {
      inBlock++;
      if (inBlock == 2) add(CalendarDayFeature.backToBack, day, 1);
      if (e.end.isAfter(blockEnd)) blockEnd = e.end;
    } else {
      blockDay = day;
      blockEnd = e.end;
      inBlock = 1;
    }
  }
  return values;
}

/// Whether a habit is used on more or fewer of the days with more of a
/// calendar feature than usual: a finding when [refusal] is null.
class CalendarDay {
  const CalendarDay({
    required this.habitId,
    required this.feature,
    required this.cut,
    required this.usableDays,
    required this.moreDays,
    this.effect,
    this.interval,
    this.pValue,
    this.refusal,
  });

  final String habitId;
  final CalendarDayFeature feature;

  /// The person's usual day, the median of the feature over its days: "more"
  /// is a day above it.
  final double cut;
  final int usableDays;

  /// Of [usableDays], those above [cut].
  final int moreDays;

  /// The share of days with a use on days above [cut], less that on the
  /// others, with the kind of day, trend and period held fixed, as a
  /// fraction.
  final double? effect;
  final Interval? interval;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  CalendarDay refused(RefusalReason reason) => CalendarDay(
    habitId: habitId,
    feature: feature,
    cut: cut,
    usableDays: usableDays,
    moreDays: moreDays,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: reason,
  );
}

/// For each habit not in [skip] and each feature with [calendarDayMinDays]
/// days above 0, whether the habit is used on more or fewer of the days
/// above the feature's median than of the rest.
///
/// What counts as a feature, its median and whether it is judged at all come
/// from the calendar's own days, never from which days held a use. The rows
/// are the days of the habit's span, up to [through] (the last whole day),
/// that the calendar covers; the response is whether the habit was used that
/// day ([DailyHabitSeries.lateDayTotal]), on the feature's indicator, whether
/// it is a weekend day (meetings are a weekday thing, and so may the habit
/// be), a trend, a level per period, and whether the habit was used the day
/// before (use comes in runs).
List<CalendarDay> calendarDays({
  required List<HabitUse> uses,
  required List<CalendarEvent> events,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final Map<CalendarDayFeature, Map<DateTime, double>> values =
      calendarDayValues(events, through: through);
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final List<String> ids =
      habits.habitIds.where((id) => !skip.contains(id)).toList()..sort();
  return <CalendarDay>[
    for (final CalendarDayFeature feature in CalendarDayFeature.values)
      if (values[feature]!.values.where((v) => v > 0).length >=
          calendarDayMinDays)
        for (final String id in ids)
          _judge(
            id,
            feature,
            values[feature]!,
            median(values[feature]!.values.toList()),
            habits,
            startOfDay(through),
            gates,
          ),
  ];
}

CalendarDay _judge(
  String id,
  CalendarDayFeature feature,
  Map<DateTime, double> values,
  double cut,
  DailyHabitSeries habits,
  DateTime through,
  InsightGates gates,
) {
  final List<DateTime> days = <DateTime>[];
  final List<double> x = <double>[];
  final List<double> y = <double>[];
  final DateTime? start = habits.firstUse(id);
  final DateTime? last = habits.lastUse(id);
  if (start != null && last != null) {
    final DateTime end = last.isBefore(through) ? last : through;
    for (final DateTime day in daysFrom(start, end)) {
      final double? value = values[day];
      if (value == null) continue;
      days.add(day);
      x.add(value > cut ? 1 : 0);
      y.add(habits.lateDayTotal(id, day) > 0 ? 1 : 0);
    }
  }
  final int more = x.where((v) => v == 1).length;
  CalendarDay result({
    RefusalReason? refusal,
    double? effect,
    Interval? interval,
    double? pValue,
  }) => CalendarDay(
    habitId: id,
    feature: feature,
    cut: cut,
    usableDays: days.length,
    moreDays: more,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: refusal,
  );

  if (days.length < gates.minDays ||
      more < gates.minExposedDays ||
      days.length - more < gates.minUnexposedDays) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  // Used every day or none: no spread to judge a difference against.
  if (sampleVariance(y) < 1e-12) {
    return result(refusal: RefusalReason.withinNoise);
  }
  final List<int> period = periodsOf(days, gates.minPeriodDays);
  if (period.last > 0 && _varyingPeriods(x, period) < gates.minMixedPeriods) {
    return result(refusal: RefusalReason.uneven);
  }
  final List<List<double>> fixed = <List<double>>[
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
    gates,
  );
  fit = widened;
  final double effect = fit.coefficients[1];
  final Interval interval = fit.interval(1, level: gates.level);
  final double p = fit.pValue(1);
  if (interval.crossesZero) {
    return result(
      refusal: RefusalReason.withinNoise,
      effect: effect,
      interval: interval,
      pValue: p,
    );
  }
  final Interval? redrawn = bootstrap(gates.level);
  if (redrawn != null && redrawn.crossesZero) {
    return result(
      refusal: RefusalReason.withinNoise,
      effect: effect,
      interval: redrawn,
      pValue: p,
    );
  }
  return result(effect: effect, interval: interval, pValue: p);
}

int _varyingPeriods(List<double> x, List<int> period) {
  final Map<int, Set<double>> seen = <int, Set<double>>{};
  for (int r = 0; r < x.length; r++) {
    seen.putIfAbsent(period[r], () => <double>{}).add(x[r]);
  }
  return seen.values.where((s) => s.length > 1).length;
}

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside]: a finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] over them all is refused as
/// [RefusalReason.chance], then one whose difference is under
/// [calendarDayFloor] as [RefusalReason.tooSmall].
List<CalendarDay> judgeCalendarDays(
  List<CalendarDay> results, {
  required List<double> alongside,
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
  return <CalendarDay>[
    for (int i = 0; i < results.length; i++)
      if (!results[i].found)
        results[i]
      else if (chance.contains(i))
        results[i].refused(RefusalReason.chance)
      else if (results[i].effect!.abs() < calendarDayFloor)
        results[i].refused(RefusalReason.tooSmall)
      else
        results[i],
  ];
}
