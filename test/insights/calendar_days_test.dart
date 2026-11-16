import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/calendar_days_copy.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart';

typedef _Journal = ({
  List<HabitUse> uses,
  List<CalendarEvent> events,
  DateTime through,
});

/// [days] days from a Monday. Each weekday has an hour of meetings, or on
/// about half of them four; weekends have none. Coffee is logged on a day
/// with chance [busy] on a four-hour day, [quiet] on the rest.
_Journal _journal(
  int seed, {
  int days = 140,
  double busy = 0.4,
  double quiet = 0.4,
}) {
  final Random r = Random(seed);
  final DateTime first = DateTime(2025, 3, 3);
  final List<HabitUse> uses = <HabitUse>[];
  final List<CalendarEvent> events = <CalendarEvent>[];
  for (int k = 0; k < days; k++) {
    final DateTime day = addDays(first, k);
    bool heavy = false;
    if (day.weekday < 6) {
      heavy = r.nextBool();
      for (int m = 0; m < (heavy ? 4 : 1); m++) {
        final DateTime start = DateTime(
          day.year,
          day.month,
          day.day,
          9 + 2 * m,
        );
        events.add(CalendarEvent(start, start.add(const Duration(hours: 1))));
      }
    }
    if (r.nextDouble() < (heavy ? busy : quiet)) {
      uses.add(
        HabitUse(
          habitId: 'Coffee',
          at: DateTime(day.year, day.month, day.day, 18),
          amount: 1,
        ),
      );
    }
  }
  return (uses: uses, events: events, through: addDays(first, days - 1));
}

CalendarDay _minutes(_Journal j) =>
    calendarDays(
      uses: j.uses,
      events: j.events,
      through: j.through,
    ).singleWhere(
      (c) =>
          c.habitId == 'Coffee' &&
          c.feature == CalendarDayFeature.meetingMinutes,
    );

void main() {
  test('a day\'s features: minutes overlap once, runs, crowded and long', () {
    final DateTime nine = DateTime(2025, 3, 3, 9);
    DateTime at(int minutes) => nine.add(Duration(minutes: minutes));
    final Map<CalendarDayFeature, Map<DateTime, double>> v =
        calendarDayValues(<CalendarEvent>[
          CalendarEvent(at(0), at(60), attendees: 6),
          CalendarEvent(at(30), at(90)),
          CalendarEvent(at(95), at(125)),
          CalendarEvent(at(300), at(305)),
          CalendarEvent(at(400), at(430), attendees: 2),
        ], through: DateTime(2025, 3, 4));
    final DateTime day = DateTime(2025, 3, 3);
    expect(v[CalendarDayFeature.meetingMinutes]![day], 150);
    expect(v[CalendarDayFeature.events]![day], 4);
    expect(v[CalendarDayFeature.backToBack]![day], 1);
    expect(v[CalendarDayFeature.crowded]![day], 1);
    expect(v[CalendarDayFeature.long]![day], 2);
    expect(v[CalendarDayFeature.events]![DateTime(2025, 3, 4)], 0);
  });

  test('a habit used on more of the busy days is found, in words', () {
    final CalendarDay c = _minutes(_journal(1, busy: 0.8, quiet: 0.15));
    expect(c.found, isTrue);
    expect(c.effect, greaterThan(calendarDayFloor));
    expect(c.cut, 60);
    expect(
      calendarDaySentence(c, 'Coffee', 'en_GB'),
      startsWith('On days with over 1 h in meetings, you log Coffee '),
    );
    expect(calendarDayRange(c, 'en_GB'), endsWith('points more often'));
    expect(calendarDayBasis(c), contains('of them with over 1 h in meetings'));
  });

  test('a habit independent of the calendar is not found', () {
    expect(_minutes(_journal(2)).found, isFalse);
  });

  test('a feature with too few days above 0 is not set against anything', () {
    final _Journal j = _journal(3);
    expect(
      calendarDays(
        uses: j.uses,
        events: j.events,
        through: j.through,
      ).where((c) => c.feature == CalendarDayFeature.crowded),
      isEmpty,
    );
  });

  test('a short span is refused as too few days, and says so', () {
    final CalendarDay c = _minutes(_journal(4, days: 18));
    expect(c.refusal, RefusalReason.tooFewDays);
    expect(
      calendarDayRefusal(c),
      'Your calendar: too few days with it yet, ${c.usableDays} of 21',
    );
  });

  test('the family can make a finding chance; a small one is too small', () {
    const CalendarDay c = CalendarDay(
      habitId: 'Coffee',
      feature: CalendarDayFeature.meetingMinutes,
      cut: 60,
      usableDays: 100,
      moreDays: 40,
      effect: 0.3,
      interval: Interval(0.1, 0.5),
      pValue: 0.01,
    );
    expect(
      judgeCalendarDays(<CalendarDay>[
        c,
      ], alongside: List<double>.filled(2000, 0.9)).single.refusal,
      RefusalReason.chance,
    );
    final CalendarDay small = CalendarDay(
      habitId: 'Coffee',
      feature: CalendarDayFeature.events,
      cut: 2,
      usableDays: 100,
      moreDays: 40,
      effect: 0.05,
      interval: const Interval(0.01, 0.09),
      pValue: 0.001,
    );
    final CalendarDay judged = judgeCalendarDays(<CalendarDay>[
      small,
    ], alongside: const <double>[]).single;
    expect(judged.refusal, RefusalReason.tooSmall);
    expect(
      calendarDayRefusal(judged),
      'Days with 3 or more calendar events: a difference too small to matter',
    );
  });

  test('the report carries calendar days through the page\'s family', () {
    final _Journal j = _journal(1, busy: 0.8, quiet: 0.15);
    final InsightsReport report = computeInsights(
      InsightsInput(
        uses: j.uses,
        outcomes: const <DailyOutcome>[],
        from: DateTime(2025, 3, 3),
        through: addDays(j.through, 1),
        events: j.events,
      ),
    );
    expect(
      report.calendarDays.where((c) => c.found).map((c) => c.feature),
      contains(CalendarDayFeature.meetingMinutes),
    );
  });

  test('counts read as whole thresholds', () {
    expect(calendarDayMore(CalendarDayFeature.long, 0), contains('a meeting'));
    expect(
      calendarDayMore(CalendarDayFeature.backToBack, 1.5),
      '2 or more runs of back-to-back meetings',
    );
    expect(
      calendarDayMore(CalendarDayFeature.meetingMinutes, 150),
      'over 2 h 30 min in meetings',
    );
  });
}
