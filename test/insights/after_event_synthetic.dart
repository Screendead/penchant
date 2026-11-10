import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/daily_series.dart';

/// A journal and a calendar for the after-an-event comparison.
typedef EventDays = ({
  List<HabitUse> uses,
  List<CalendarEvent> events,
  DateTime through,
});

/// [days] days from a Monday. Weekdays hold up to four meetings of 30 to 60
/// minutes between 09:00 and 17:00. Coffee is logged [perDay] times a weekday
/// at random work-hour times and once on half of weekend days, all
/// independent of the meetings; with [follow], each meeting block's end is
/// also followed by a use within 50 minutes with that chance.
EventDays eventDays(
  int seed, {
  int days = 120,
  int perDay = 3,
  double follow = 0,
}) {
  final Random r = Random(seed);
  final DateTime first = DateTime(2025, 3, 3);
  final List<HabitUse> uses = <HabitUse>[];
  final List<CalendarEvent> events = <CalendarEvent>[];
  DateTime at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
  void use(DateTime t) =>
      uses.add(HabitUse(habitId: 'Coffee', at: t, amount: 1));
  for (int k = 0; k < days; k++) {
    final DateTime day = addDays(first, k);
    if (day.weekday >= 6) {
      if (r.nextBool()) use(at(day, 9 * 60 + r.nextInt(8 * 60)));
      continue;
    }
    for (int u = 0; u < perDay; u++) {
      use(at(day, 9 * 60 + r.nextInt(8 * 60)));
    }
    final int meetings = r.nextInt(5);
    final List<CalendarEvent> today = <CalendarEvent>[
      for (int m = 0; m < meetings; m++)
        () {
          final DateTime start = at(day, 9 * 60 + 30 * r.nextInt(15));
          return CalendarEvent(
            start,
            start.add(Duration(minutes: 30 + 15 * r.nextInt(3))),
          );
        }(),
    ];
    events.addAll(today);
    if (follow > 0) {
      for (final CalendarEvent b in eventBlocks(today)) {
        if (r.nextDouble() < follow) {
          use(b.end.add(Duration(minutes: 1 + r.nextInt(50))));
        }
      }
    }
  }
  return (uses: uses, events: events, through: addDays(first, days - 1));
}
