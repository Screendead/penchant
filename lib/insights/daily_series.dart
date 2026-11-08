import 'package:tracker/data/day.dart';

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

/// Each habit's total per local calendar day. A day with no entry for a habit
/// is a day it was not used.
class DailyHabitSeries {
  DailyHabitSeries._(this._totals, this.firstDay, this.lastDay);

  factory DailyHabitSeries.fromUses(Iterable<HabitUse> uses) {
    final Map<String, Map<DateTime, double>> totals =
        <String, Map<DateTime, double>>{};
    DateTime? first, last;
    for (final HabitUse use in uses) {
      final DateTime day = startOfDay(use.at);
      final Map<DateTime, double> days = totals.putIfAbsent(
        use.habitId,
        () => <DateTime, double>{},
      );
      days[day] = (days[day] ?? 0) + use.amount;
      if (first == null || day.isBefore(first)) first = day;
      if (last == null || day.isAfter(last)) last = day;
    }
    return DailyHabitSeries._(totals, first, last);
  }

  final Map<String, Map<DateTime, double>> _totals;

  /// The first and last days with any use; null for an empty journal.
  final DateTime? firstDay;
  final DateTime? lastDay;

  Iterable<String> get habitIds => _totals.keys;

  double total(String habitId, DateTime day) =>
      _totals[habitId]?[startOfDay(day)] ?? 0;
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

  Iterable<String> get metricIds => _values.keys;

  double? value(String metricId, DateTime day) =>
      _values[metricId]?[startOfDay(day)];
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
