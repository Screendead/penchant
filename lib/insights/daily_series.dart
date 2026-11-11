import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/step_changes.dart';

/// One logged use of a habit, at a local time.
class HabitUse {
  const HabitUse({
    required this.habitId,
    required this.at,
    required this.amount,
  });

  final String habitId;
  final DateTime at;
  final num amount;
}

/// One value of an outcome (a night's sleep, a day's resting heart rate) for
/// the local calendar day it describes. [date] is read in the device's time
/// zone: pass a local DateTime, since a UTC midnight can fall on the previous
/// local day.
class DailyOutcome {
  DailyOutcome({
    required DateTime date,
    required this.metricId,
    required this.value,
  }) : date = startOfDay(date);

  final DateTime date;
  final String metricId;
  final double value;
}

/// The hour before which a use counts as the previous day's late use: a 01:00
/// entry ends the evening before it, so it is read as 25:00 of that day and
/// adds to that day's [DailyHabitSeries.lateDayTotal]. [DailyHabitSeries.total]
/// stays on the calendar day.
const int lateUseCutoffHour = 5;

/// The day whose evening [at] belongs to: its calendar day, or the day before
/// when it falls before [lateUseCutoffHour].
DateTime lateDayOf(DateTime at) =>
    at.hour < lateUseCutoffHour ? addDays(startOfDay(at), -1) : startOfDay(at);

/// Each habit's total per local calendar day. A day with no entry for a habit
/// is a day it was not used.
///
/// Only entries with a positive amount count as use: a zero-quantity entry
/// (legacy data has them) adds nothing and moves no first or last day.
class DailyHabitSeries {
  DailyHabitSeries._(
    this._totals,
    this._spans,
    this._lastUse,
    this._lateTotals,
  );

  factory DailyHabitSeries.fromUses(Iterable<HabitUse> uses) {
    final Map<String, Map<DateTime, double>> totals =
        <String, Map<DateTime, double>>{};
    final Map<String, (DateTime, DateTime)> spans =
        <String, (DateTime, DateTime)>{};
    final Map<String, Map<DateTime, int>> lastUse =
        <String, Map<DateTime, int>>{};
    final Map<String, Map<DateTime, double>> lateTotals =
        <String, Map<DateTime, double>>{};
    for (final HabitUse use in uses) {
      final Map<DateTime, double> days = totals.putIfAbsent(
        use.habitId,
        () => <DateTime, double>{},
      );
      if (use.amount <= 0) continue;
      final DateTime day = startOfDay(use.at);
      days[day] = (days[day] ?? 0) + use.amount;
      final DateTime lateDay = lateDayOf(use.at);
      // Clock time, so a DST change moves no use; past midnight it runs on
      // from 24:00.
      final int minutes =
          use.at.hour * 60 +
          use.at.minute +
          (lateDay == day ? 0 : Duration.minutesPerDay);
      final Map<DateTime, int> last = lastUse.putIfAbsent(
        use.habitId,
        () => <DateTime, int>{},
      );
      last[lateDay] = max(last[lateDay] ?? minutes, minutes);
      final Map<DateTime, double> late = lateTotals.putIfAbsent(
        use.habitId,
        () => <DateTime, double>{},
      );
      late[lateDay] = (late[lateDay] ?? 0) + use.amount;
      final (DateTime, DateTime)? span = spans[use.habitId];
      spans[use.habitId] = span == null
          ? (day, day)
          : (
              day.isBefore(span.$1) ? day : span.$1,
              day.isAfter(span.$2) ? day : span.$2,
            );
    }
    return DailyHabitSeries._(totals, spans, lastUse, lateTotals);
  }

  final Map<String, Map<DateTime, double>> _totals;
  final Map<String, (DateTime, DateTime)> _spans;
  final Map<String, Map<DateTime, int>> _lastUse;
  final Map<String, Map<DateTime, double>> _lateTotals;

  /// Every habit with an entry, including one whose entries are all zero.
  Iterable<String> get habitIds => _totals.keys;

  double total(String habitId, DateTime day) =>
      _totals[habitId]?[startOfDay(day)] ?? 0;

  /// Minutes after [day]'s midnight of [habitId]'s last use that day, on the
  /// day [lateDayOf] gives it; null on a day without one.
  int? lastUseMinutes(String habitId, DateTime day) =>
      _lastUse[habitId]?[startOfDay(day)];

  /// [habitId]'s total over the uses [lastUseMinutes] counts on [day].
  double lateDayTotal(String habitId, DateTime day) =>
      _lateTotals[habitId]?[startOfDay(day)] ?? 0;

  /// The days [lastUseMinutes] has a value for, in no order.
  Iterable<DateTime> lateDays(String habitId) =>
      _lastUse[habitId]?.keys ?? const <DateTime>[];

  /// The first and last days [habitId] was used; null when it never was.
  DateTime? firstUse(String habitId) => _spans[habitId]?.$1;
  DateTime? lastUse(String habitId) => _spans[habitId]?.$2;

  /// The first and last days any habit was used; null when none was.
  DateTime? get firstDay => _spans.values.isEmpty
      ? null
      : _spans.values.map((s) => s.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get lastDay => _spans.values.isEmpty
      ? null
      : _spans.values.map((s) => s.$2).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Outcome values by metric and day. Several values for one metric on one day
/// are averaged; a day without one is missing, never zero.
class OutcomeSeries {
  OutcomeSeries._(this._values);

  factory OutcomeSeries.fromOutcomes(Iterable<DailyOutcome> outcomes) {
    final Map<String, Map<DateTime, List<double>>> grouped =
        <String, Map<DateTime, List<double>>>{};
    for (final DailyOutcome o in outcomes) {
      grouped
          .putIfAbsent(o.metricId, () => <DateTime, List<double>>{})
          .putIfAbsent(o.date, () => <double>[])
          .add(o.value);
    }
    return OutcomeSeries._(<String, Map<DateTime, double>>{
      for (final MapEntry<String, Map<DateTime, List<double>>> metric
          in grouped.entries)
        metric.key: <DateTime, double>{
          for (final MapEntry<DateTime, List<double>> day
              in metric.value.entries)
            day.key:
                day.value.fold<double>(0, (s, v) => s + v) / day.value.length,
        },
    });
  }

  final Map<String, Map<DateTime, double>> _values;
  final Map<String, LevelShifts> _shifts = <String, LevelShifts>{};

  Iterable<String> get metricIds => _values.keys;

  /// [metricId]'s lasting changes of level over every day it has a value.
  LevelShifts shifts(String metricId) => _shifts.putIfAbsent(
    metricId,
    () => levelShifts(_values[metricId] ?? const <DateTime, double>{}),
  );

  double? value(String metricId, DateTime day) =>
      _values[metricId]?[startOfDay(day)];

  /// [metricId]'s value on each day that has one, in no order.
  Map<DateTime, double> days(String metricId) =>
      Map<DateTime, double>.unmodifiable(
        _values[metricId] ?? const <DateTime, double>{},
      );
}

/// Every local calendar day from [from] to [through], both included.
Iterable<DateTime> daysFrom(DateTime from, DateTime through) sync* {
  for (
    DateTime day = startOfDay(from);
    !day.isAfter(through);
    day = addDays(day, 1)
  ) {
    yield day;
  }
}
