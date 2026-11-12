import 'package:intl/intl.dart';
import 'package:tracker/insights/calendar_days.dart';
import 'package:tracker/insights/what_follows.dart';

String _points(double fraction, String locale) =>
    NumberFormat.decimalPattern(locale).format((fraction * 100).round());

String _duration(double minutes) {
  final int total = minutes.round();
  final int h = total ~/ 60, m = total % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// What a day "above usual" holds: "over 2 h 30 min in meetings", "3 or more
/// calendar events", "back-to-back meetings".
String calendarDayMore(CalendarDayFeature feature, double cut) {
  if (feature == CalendarDayFeature.meetingMinutes) {
    return cut == 0 ? 'time in meetings' : 'over ${_duration(cut)} in meetings';
  }
  // Counts are whole, so "above a median of 2.5" is "3 or more".
  final int least = cut.floor() + 1;
  return switch (feature) {
    CalendarDayFeature.events =>
      least == 1 ? 'a calendar event' : '$least or more calendar events',
    CalendarDayFeature.backToBack =>
      least == 1
          ? 'back-to-back meetings'
          : '$least or more runs of back-to-back meetings',
    CalendarDayFeature.crowded =>
      least == 1
          ? 'a meeting of $calendarCrowdedAttendees or more people'
          : '$least or more meetings of $calendarCrowdedAttendees or more '
                'people',
    CalendarDayFeature.long =>
      least == 1
          ? 'a meeting over $calendarLongMinutes minutes'
          : '$least or more meetings over $calendarLongMinutes minutes',
    CalendarDayFeature.meetingMinutes => throw StateError('handled above'),
  };
}

/// The findings among [results], largest difference first.
List<CalendarDay> calendarDayCards(List<CalendarDay> results) =>
    results.where((c) => c.found).toList()..sort((a, b) {
      final int bySize = b.effect!.abs().compareTo(a.effect!.abs());
      return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
    });

/// "On days with over 2 h in meetings, you log Coffee 18 points more often
/// than on other days."
String calendarDaySentence(CalendarDay finding, String habit, String locale) =>
    'On days with ${calendarDayMore(finding.feature, finding.cut)}, you log '
    '$habit ${_points(finding.effect!.abs(), locale)} points '
    '${finding.effect! > 0 ? 'more' : 'less'} often than on other days.';

/// "Range: 8 to 29 points more often"; both ends share a sign.
String calendarDayRange(CalendarDay finding, String locale) {
  final double low = finding.interval!.low, high = finding.interval!.high;
  final bool more = finding.effect! > 0;
  final (double near, double far) = more ? (low, high) : (-high, -low);
  return 'Range: ${_points(near, locale)} to ${_points(far, locale)} points '
      '${more ? 'more' : 'less'} often';
}

/// "From 120 days of your calendar, 48 of them with over 2 h in meetings,
/// weekdays set against weekdays".
String calendarDayBasis(CalendarDay finding) =>
    'From ${finding.usableDays} days of your calendar, ${finding.moreDays} '
    'of them with ${calendarDayMore(finding.feature, finding.cut)}, weekdays '
    'set against weekdays';

/// [finding] as the lines "Copy as text" writes.
List<String> calendarDayText(
  CalendarDay finding,
  String habit,
  String locale,
) => <String>[
  habit,
  calendarDaySentence(finding, habit, locale),
  calendarDayRange(finding, locale),
  calendarDayBasis(finding),
];

/// Why [refusal] is not shown, in words.
String calendarDayRefusal(
  CalendarDay refusal, {
  InsightGates gates = const InsightGates(),
}) {
  final String more = calendarDayMore(refusal.feature, refusal.cut);
  return switch (refusal.refusal) {
    RefusalReason.tooSmall =>
      'Days with $more: a difference too small to matter',
    RefusalReason.chance =>
      'Days with $more: a difference that could be chance, among everything '
          'this page checks',
    RefusalReason.uneven =>
      'Days with $more: they fall in too few months to tell from the time of '
          'year',
    RefusalReason.tooFewDays when refusal.usableDays < gates.minDays =>
      'Your calendar: too few days with it yet, ${refusal.usableDays} of '
          '${gates.minDays}',
    RefusalReason.tooFewDays =>
      'Days with $more: too few of them, or too few without, to compare',
    _ => 'Days with $more: no clear difference from other days',
  };
}
