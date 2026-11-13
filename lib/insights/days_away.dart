import 'package:tracker/data/day.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Where the person was stays on the device, in the sealed device file
// `places`, as coarse cells per day: nothing here is logged or reported.

/// A coarse cell of the map, a tenth of a degree each way (about 11 km north
/// to south): latitude and longitude times ten, rounded down.
typedef DayCell = (int, int);

DayCell dayCellOf(double latitude, double longitude) =>
    ((latitude * 10).floor(), (longitude * 10).floor());

double _cellDistanceKm(DayCell a, DayCell b) =>
    distanceMeters(
      (a.$1 + 0.5) / 10,
      (a.$2 + 0.5) / 10,
      (b.$1 + 0.5) / 10,
      (b.$2 + 0.5) / 10,
    ) /
    1000;

/// A day is away when a photo or visit that day was farther than this from
/// home: past a commute or a night out, short of nothing but travel.
const double awayKm = 75;

/// Cells this near each other are one home, so a home on a cell's edge is
/// not split in two.
const double _homeKm = 25;

/// Home on a day is judged from the days this many either side of it, so a
/// move of house moves it within about this long.
const int homeWindowDays = 90;

/// Home is judged afresh for each block of this many days.
const int _homeBlockDays = 30;

/// A run of this many days or fewer with no photo or visit at all, between
/// two away days, is away too: a trip goes on through the days nothing was
/// photographed.
const int awayFillDays = 2;

/// The fewest away days before any habit is set against them, as for a
/// calendar feature ([calendarDayMinDays]).
const int daysAwayMinDays = calendarDayMinDays;

/// Each day from the first with a cell through [through]: true when away
/// from home, false when at home or unknown. [cells] are the coarse cells of
/// the photos and visits of each day (keyed by local midnight).
///
/// Home is, for each block of days, the cell whose neighbourhood (cells
/// within 25 km) holds the most days with a photo or visit among the
/// [homeWindowDays] either side; the person is assumed to have one home at a
/// time. A day with no photo or visit counts as home unless it lies in a
/// short gap ([awayFillDays]) between two away days.
Map<DateTime, bool> daysAwayFrom(
  Map<DateTime, Set<DayCell>> cells, {
  required DateTime through,
}) {
  final List<DateTime> known =
      cells.keys.where((d) => cells[d]!.isNotEmpty).toList()..sort();
  final DateTime last = startOfDay(through);
  if (known.isEmpty || known.first.isAfter(last)) return <DateTime, bool>{};
  final DateTime first = known.first;

  DayCell? homeAround(DateTime centre, int window) {
    final DateTime from = addDays(centre, -window);
    final DateTime to = addDays(centre, window);
    final List<Set<DayCell>> inWindow = <Set<DayCell>>[
      for (final DateTime d in known)
        if (!d.isBefore(from) && !d.isAfter(to)) cells[d]!,
    ];
    final Set<DayCell> candidates = <DayCell>{
      for (final Set<DayCell> c in inWindow) ...c,
    };
    DayCell? best;
    int bestDays = 0;
    for (final DayCell c in candidates) {
      int days = 0;
      for (final Set<DayCell> day in inWindow) {
        if (day.any((d) => _cellDistanceKm(c, d) <= _homeKm)) days++;
      }
      if (days > bestDays ||
          (days == bestDays &&
              best != null &&
              (c.$1 < best.$1 || (c.$1 == best.$1 && c.$2 < best.$2)))) {
        best = c;
        bestDays = days;
      }
    }
    return best;
  }

  final Map<DateTime, bool> away = <DateTime, bool>{};
  DateTime blockStart = first;
  while (!blockStart.isAfter(last)) {
    final DayCell? home = homeAround(
      addDays(blockStart, _homeBlockDays ~/ 2),
      homeWindowDays,
    );
    for (int i = 0; i < _homeBlockDays; i++) {
      final DateTime d = addDays(blockStart, i);
      if (d.isAfter(last)) break;
      final Set<DayCell>? day = cells[d];
      away[d] =
          home != null &&
          day != null &&
          day.any((c) => _cellDistanceKm(c, home) > awayKm);
    }
    blockStart = addDays(blockStart, _homeBlockDays);
  }

  // Fill short gaps with nothing known between two away days.
  final List<DateTime> days = away.keys.toList()..sort();
  for (int i = 0; i < days.length; i++) {
    if (!away[days[i]]!) continue;
    int j = i + 1;
    while (j < days.length && (cells[days[j]]?.isEmpty ?? true)) {
      j++;
    }
    final int gap = j - i - 1;
    if (gap > 0 && gap <= awayFillDays && j < days.length && away[days[j]]!) {
      for (int k = i + 1; k < j; k++) {
        away[days[k]] = true;
      }
    }
  }
  return away;
}

/// Whether a habit is used on more or fewer of the days away from home: a
/// finding when [refusal] is null.
class DaysAway {
  const DaysAway({
    required this.habitId,
    required this.usableDays,
    required this.awayDays,
    this.effect,
    this.interval,
    this.pValue,
    this.refusal,
  });

  final String habitId;
  final int usableDays;

  /// Of [usableDays], those away.
  final int awayDays;

  /// The share of away days with a use, less that of the others, with the
  /// kind of day, trend, period and the day before's use held fixed, as a
  /// fraction.
  final double? effect;
  final Interval? interval;
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  DaysAway refused(RefusalReason reason) => DaysAway(
    habitId: habitId,
    usableDays: usableDays,
    awayDays: awayDays,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: reason,
  );
}

/// For each habit not in [skip], whether it is used on more or fewer of the
/// [away] days than of the rest, judged as a calendar feature is
/// ([fitDayIndicator]); nothing while [away] holds fewer than
/// [daysAwayMinDays] away days.
List<DaysAway> daysAway({
  required List<HabitUse> uses,
  required Map<DateTime, bool> away,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  if (away.values.where((a) => a).length < daysAwayMinDays) {
    return const <DaysAway>[];
  }
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final List<String> ids =
      habits.habitIds.where((id) => !skip.contains(id)).toList()..sort();
  return <DaysAway>[
    for (final String id in ids)
      if (fitDayIndicator(id, away, habits, startOfDay(through), gates)
          case final DayIndicatorFit fit)
        DaysAway(
          habitId: id,
          usableDays: fit.usableDays,
          awayDays: fit.moreDays,
          effect: fit.effect,
          interval: fit.interval,
          pValue: fit.pValue,
          refusal: fit.refusal,
        ),
  ];
}

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside], as [judgeCalendarDays] judges, with the same
/// floor.
List<DaysAway> judgeDaysAway(
  List<DaysAway> results, {
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
  return <DaysAway>[
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
