import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/step_changes.dart';

// Health values stay on the device: nothing here is logged or reported.

/// The days of a habit's use read on each side of a shift, and the fewest
/// that must lie in the journal.
const int habitChangeReach = 28;
const int minHabitChangeDays = 14;

/// A habit's daily amount changes with a shift when the two sides differ by
/// this ratio, beyond this chance of the days' own spread.
const double habitChangeRatio = 1.5;
const double habitChangeSignificance = 0.01;

/// A habit whose daily amount changed when a measure's level did.
class HabitChange {
  const HabitChange({
    required this.habitId,
    required this.before,
    required this.after,
  });

  final String habitId;

  /// The mean amount a day over the [habitChangeReach] days before the shift
  /// and from it.
  final double before;
  final double after;
}

/// One measure's lasting change of level, and the habits that changed with
/// it.
class MeasureShift {
  const MeasureShift({
    required this.metricId,
    required this.shift,
    this.habits = const <HabitChange>[],
    this.found = false,
  });

  final String metricId;
  final LevelShift shift;

  /// By habit id; never an archived habit.
  final List<HabitChange> habits;

  /// Whether it stands out among every comparison in the report and is at
  /// least the measure's floor. Set by [judgeMeasureShifts].
  final bool found;
}

/// Every shift in the measures the page names, unjudged, with [searched]:
/// the p-value of each measure searched that has none, so the report's family
/// counts every search made.
({List<MeasureShift> shifts, List<double> searched}) measureShifts({
  required OutcomeSeries outcomes,
  required DailyHabitSeries habits,
  required DateTime through,
  int lagDays = insightsLagDays,
  Set<String> skip = const <String>{},
}) {
  final List<MeasureShift> shifts = <MeasureShift>[];
  final List<double> searched = <double>[];
  final List<String> metricIds = outcomes.metricIds.toList()..sort();
  for (final String metricId in metricIds) {
    if (metricCopy(metricId) == null) continue;
    final LevelShifts found = outcomes.shifts(metricId);
    if (found.shifts.isEmpty) {
      if (found.pValue case final double p) searched.add(p);
      continue;
    }
    for (final LevelShift shift in found.shifts) {
      shifts.add(
        MeasureShift(
          metricId: metricId,
          shift: shift,
          habits: _habitChanges(
            habits,
            addDays(shift.at, -lagDays),
            through,
            skip,
          ),
        ),
      );
    }
  }
  return (shifts: shifts, searched: searched);
}

// The habits whose amount a day differs between the days before [day] and
// those from it. Days before the journal's first entry or after [through] are
// not days without a habit.
List<HabitChange> _habitChanges(
  DailyHabitSeries habits,
  DateTime day,
  DateTime through,
  Set<String> skip,
) {
  DateTime? first;
  for (final String id in habits.habitIds) {
    final DateTime? f = habits.firstUse(id);
    if (f != null && (first == null || f.isBefore(first))) first = f;
  }
  if (first == null) return const <HabitChange>[];
  final DateTime from = addDays(day, -habitChangeReach);
  final DateTime to = addDays(day, habitChangeReach - 1);
  final List<DateTime> before = <DateTime>[
    for (final DateTime d in daysFrom(
      from.isBefore(first) ? first : from,
      addDays(day, -1),
    ))
      d,
  ];
  final List<DateTime> after = <DateTime>[
    for (final DateTime d in daysFrom(day, to.isAfter(through) ? through : to))
      d,
  ];
  if (before.length < minHabitChangeDays || after.length < minHabitChangeDays) {
    return const <HabitChange>[];
  }
  final List<String> ids = habits.habitIds.toList()..sort();
  return <HabitChange>[
    for (final String id in ids)
      if (!skip.contains(id))
        if (_changed(
              <double>[for (final DateTime d in before) habits.total(id, d)],
              <double>[for (final DateTime d in after) habits.total(id, d)],
            )
            case (final double a, final double b))
          HabitChange(habitId: id, before: a, after: b),
  ];
}

// Days of use come in runs, so each side's days are not independent: the
// standard error is widened by their lag-1 autocorrelation within the sides,
// as in unevenHalves.
(double, double)? _changed(List<double> before, List<double> after) {
  final double a = mean(before), b = mean(after);
  if (max(a, b) <= 0 || max(a, b) < habitChangeRatio * min(a, b)) return null;
  final double va = sampleVariance(before) / before.length;
  final double vb = sampleVariance(after) / after.length;
  if (va + vb > 0) {
    double lagged = 0, squares = 0;
    for (final (List<double> side, double m) in <(List<double>, double)>[
      (before, a),
      (after, b),
    ]) {
      for (int i = 0; i < side.length; i++) {
        squares += (side[i] - m) * (side[i] - m);
        if (i > 0) lagged += (side[i] - m) * (side[i - 1] - m);
      }
    }
    final double rho = (lagged / squares).clamp(0.0, 0.9);
    final double df =
        (va + vb) *
        (va + vb) /
        (va * va / (before.length - 1) + vb * vb / (after.length - 1));
    final double t = (a - b) / sqrt((va + vb) * (1 + rho) / (1 - rho));
    if (studentTTwoSided(t, df) >= habitChangeSignificance) return null;
  }
  return (a, b);
}

/// [shifts] with [MeasureShift.found] set: Benjamini-Hochberg at [q] over
/// their p-values and [alongside] (the searches that found none and the
/// report's other comparisons), then each measure's floor.
List<MeasureShift> judgeMeasureShifts(
  List<MeasureShift> shifts, {
  List<double> alongside = const <double>[],
  Map<String, double> floors = const <String, double>{},
  required double q,
}) {
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final MeasureShift s in shifts) s.shift.pValue,
    ...alongside,
  ], q);
  return <MeasureShift>[
    for (final (int i, MeasureShift s) in shifts.indexed)
      MeasureShift(
        metricId: s.metricId,
        shift: s.shift,
        habits: s.habits,
        found:
            kept[i] && s.shift.change.abs() >= metricFloor(s.metricId, floors),
      ),
  ];
}

String _number(double value, int decimals, String locale) =>
    NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: decimals,
    ).format(value);

int _decimals(MeasureShift s) {
  final MetricCopy copy = metricCopy(s.metricId)!;
  int digits = copy.decimals;
  while (digits < 3 &&
      s.shift.change.abs() * copy.scale < 0.5 * pow(10, -digits)) {
    digits++;
  }
  return digits;
}

/// "From 12 March 2026, your resting heart rate averaged 4 bpm higher than
/// before." [date] is the shift's day as the page writes dates.
String measureShiftSentence(MeasureShift s, String date, String locale) {
  final MetricCopy copy = metricCopy(s.metricId)!;
  final String size = measureAmount(s.shift.change, copy, _decimals(s), locale);
  return 'From $date, your ${copy.name} averaged $size '
      '${copy.direction(s.shift.change)} than before.';
}

/// "58 bpm over the 43 days before, 62 bpm over the 60 days from then".
String measureShiftBasis(MeasureShift s, String locale) {
  final MetricCopy copy = metricCopy(s.metricId)!;
  final int digits = _decimals(s);
  String level(double v) => measureLevel(v, copy, digits, locale);
  return '${level(s.shift.before)} over the ${s.shift.daysBefore} days '
      'before, ${level(s.shift.after)} over the ${s.shift.daysAfter} days '
      'from then';
}

/// "Coffee changed around then too, from 1.5 a day to 3.5, so the two can’t
/// be told apart." The habit's name comes first with a past-tense verb, which
/// agrees with a plural or uncountable name as well.
String habitChangeLine(HabitChange change, String habit, String locale) =>
    '$habit changed around then too, from '
    '${_number(change.before, 1, locale)} a day to '
    '${_number(change.after, 1, locale)}, so the two can’t be told apart.';

/// One shift as the page shows it, for "Copy as text".
List<String> measureShiftText(
  MeasureShift s,
  String date,
  String Function(String habitId) nameOf,
  String locale,
) => <String>[
  measureShiftSentence(s, date, locale),
  measureShiftBasis(s, locale),
  for (final HabitChange c in s.habits)
    habitChangeLine(c, nameOf(c.habitId), locale),
];
