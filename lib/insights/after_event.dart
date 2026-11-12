import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/hours_after.dart' show anyTimeIn;
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

// Calendar events stay on the device: nothing here is logged or reported.

/// A timed calendar event: when it starts and ends and how many people it
/// lists, and nothing else.
class CalendarEvent {
  const CalendarEvent(this.start, this.end, {this.attendees = 0});

  final DateTime start;
  final DateTime end;

  /// How many people the event lists; 0 when it lists none.
  final int attendees;
}

/// The window after an event's end that counts as "after it".
const int afterEventMinutes = 60;

/// Events shorter than this are left out: reminders and holds, not meetings.
const int afterEventMinEventMinutes = 15;

/// A gap this short between two events joins them into one block, whose end
/// alone is judged.
const int afterEventJoinMinutes = 10;

/// A control moment needs no event in this long before it, nor in the
/// window after it.
const int afterEventQuietMinutes = 120;

/// How far, in days, a control moment may be from its event.
const int afterEventControlReachDays = 14;

/// The fewest days with a matched event the comparison needs.
const int afterEventMinDays = 14;

/// The smallest difference in the share of windows with a use worth
/// showing, as a fraction.
const double afterEventFloor = 0.10;

/// Whether a habit is used in the hour after a calendar event ends more or
/// less often than in the same hour of a nearby day with no event: a finding
/// when [refusal] is null.
class AfterEvent {
  const AfterEvent({
    required this.habitId,
    required this.eventDays,
    required this.controlDays,
    required this.eventRate,
    required this.controlRate,
    this.effect,
    this.interval,
    this.pValue,
    this.refusal,
  });

  final String habitId;

  /// Days with at least one event matched to a control moment.
  final int eventDays;

  /// Days holding at least one of those control moments.
  final int controlDays;

  /// Over [eventDays], the mean share of a day's windows after an event
  /// holding a use.
  final double eventRate;

  /// Over [controlDays], the mean share of a day's control windows holding a
  /// use.
  final double controlRate;

  /// The mean share of a day's windows after an event holding a use, less
  /// the mean share of a control day's windows, as a fraction.
  final double? effect;
  final Interval? interval;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;
  final RefusalReason? refusal;

  bool get found => refusal == null;

  AfterEvent refused(RefusalReason reason) => AfterEvent(
    habitId: habitId,
    eventDays: eventDays,
    controlDays: controlDays,
    eventRate: eventRate,
    controlRate: controlRate,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: reason,
  );
}

/// [events] of at least [afterEventMinEventMinutes] as blocks, sorted, each
/// joining events that overlap or are under [afterEventJoinMinutes] apart.
List<CalendarEvent> eventBlocks(Iterable<CalendarEvent> events) {
  final List<CalendarEvent> timed =
      events
          .where(
            (e) =>
                e.end.difference(e.start).inMinutes >=
                afterEventMinEventMinutes,
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final List<CalendarEvent> blocks = <CalendarEvent>[];
  const Duration join = Duration(minutes: afterEventJoinMinutes);
  for (final CalendarEvent e in timed) {
    if (blocks.isNotEmpty && !e.start.isAfter(blocks.last.end.add(join))) {
      final CalendarEvent last = blocks.removeLast();
      blocks.add(
        CalendarEvent(last.start, e.end.isAfter(last.end) ? e.end : last.end),
      );
    } else {
      blocks.add(e);
    }
  }
  return blocks;
}

// Whether any block overlaps [from, to). Blocks are sorted by start and never
// overlap one another, so their ends are sorted too.
bool _anyBlockIn(List<CalendarEvent> blocks, DateTime from, DateTime to) {
  int low = 0, high = blocks.length;
  while (low < high) {
    final int mid = (low + high) >> 1;
    if (blocks[mid].end.isAfter(from)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low < blocks.length && blocks[low].start.isBefore(to);
}

/// For each habit not in [skip], whether it is used in the
/// [afterEventMinutes] after a block of calendar events ends (see
/// [eventBlocks]) more often than at the same clock time on a nearby day.
///
/// Each block end on a day of the habit's span, up to [through] (the last
/// whole day), is matched to the same wall-clock time on the nearest day
/// within [afterEventControlReachDays] that is also a weekend day or also a
/// weekday, lies in the span, and holds no block in the
/// [afterEventQuietMinutes] before that time or the window after it. The
/// unit is the day, on each side: the share of a day's windows after an
/// event holding a use against the share of a control day's windows, on an
/// intercept and a side indicator. A control day nearby events share counts
/// once, since counting it per event would make those events' days move
/// together. The same clock time and kind of day hold fixed the habit's own
/// rhythm, which work hours share with meetings.
List<AfterEvent> afterEvent({
  required List<HabitUse> uses,
  required List<CalendarEvent> events,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final List<CalendarEvent> blocks = eventBlocks(events);
  if (blocks.isEmpty) return const <AfterEvent>[];
  final Map<String, List<DateTime>> usesOf = <String, List<DateTime>>{};
  for (final HabitUse u in uses) {
    if (u.amount > 0) usesOf.putIfAbsent(u.habitId, () => []).add(u.at);
  }
  final DateTime last = startOfDay(through);
  final List<String> ids =
      usesOf.keys.where((id) => !skip.contains(id)).toList()..sort();
  return <AfterEvent>[
    for (final String id in ids)
      _judge(id, usesOf[id]!..sort(), blocks, last, gates),
  ];
}

AfterEvent _judge(
  String id,
  List<DateTime> times,
  List<CalendarEvent> blocks,
  DateTime through,
  InsightGates gates,
) {
  const Duration window = Duration(minutes: afterEventMinutes);
  const Duration quiet = Duration(minutes: afterEventQuietMinutes);
  final DateTime start = startOfDay(times.first);
  final DateTime lastUse = startOfDay(times.last);
  final DateTime end = lastUse.isBefore(through) ? lastUse : through;
  bool inSpan(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
  bool weekend(DateTime day) => day.weekday >= 6;
  bool usedIn(DateTime from) => anyTimeIn(times, from, from.add(window));

  // Per day and side: uses in the windows, and the windows.
  final Map<(DateTime, bool), List<double>> byDay =
      <(DateTime, bool), List<double>>{};
  void add(DateTime day, bool control, bool used) {
    final List<double> sums = byDay.putIfAbsent((
      day,
      control,
    ), () => <double>[0, 0]);
    sums[0] += used ? 1 : 0;
    sums[1] += 1;
  }

  for (final CalendarEvent b in blocks) {
    final DateTime day = startOfDay(b.end);
    if (!inSpan(day)) continue;
    DateTime? control;
    for (int k = 1; k <= afterEventControlReachDays && control == null; k++) {
      for (final int sign in const <int>[1, -1]) {
        final DateTime other = addDays(day, sign * k);
        if (!inSpan(other) || weekend(other) != weekend(day)) continue;
        final DateTime at = DateTime(
          other.year,
          other.month,
          other.day,
          b.end.hour,
          b.end.minute,
        );
        if (_anyBlockIn(blocks, at.subtract(quiet), at.add(window))) continue;
        control = at;
        break;
      }
    }
    if (control == null) continue;
    final bool e = usedIn(b.end), c = usedIn(control);
    add(day, false, e);
    add(startOfDay(control), true, c);
  }
  final List<double> y = <double>[];
  final List<double> side = <double>[];
  for (final MapEntry<(DateTime, bool), List<double>> e in byDay.entries) {
    y.add(e.value[0] / e.value[1]);
    side.add(e.key.$2 ? 0 : 1);
  }
  final int exposed = side.where((v) => v == 1).length;
  double sideMean(double s) {
    final List<double> on = <double>[
      for (int r = 0; r < y.length; r++)
        if (side[r] == s) y[r],
    ];
    return on.isEmpty ? 0 : mean(on);
  }

  AfterEvent result({
    RefusalReason? refusal,
    double? effect,
    Interval? interval,
    double? pValue,
  }) => AfterEvent(
    habitId: id,
    eventDays: exposed,
    controlDays: y.length - exposed,
    eventRate: sideMean(1),
    controlRate: sideMean(0),
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: refusal,
  );
  final int least = max(afterEventMinDays, gates.minExposedDays);
  if (exposed < least || y.length - exposed < least) {
    return result(refusal: RefusalReason.tooFewDays);
  }
  // Every day the same share: no spread to judge a difference against.
  if (sampleVariance(y) < 1e-12) {
    return result(refusal: RefusalReason.withinNoise);
  }
  final LinearFit? fit = fitLeastSquares(<List<double>>[
    for (int r = 0; r < y.length; r++) <double>[1, side[r]],
  ], y);
  if (fit == null) return result(refusal: RefusalReason.tooFewDays);
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
/// [RefusalReason.chance], then one whose difference is under
/// [afterEventFloor] as [RefusalReason.tooSmall].
List<AfterEvent> judgeAfterEvent(
  List<AfterEvent> results, {
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
  return <AfterEvent>[
    for (int i = 0; i < results.length; i++)
      if (!results[i].found)
        results[i]
      else if (chance.contains(i))
        results[i].refused(RefusalReason.chance)
      else if (results[i].effect!.abs() < afterEventFloor)
        results[i].refused(RefusalReason.tooSmall)
      else
        results[i],
  ];
}
