import 'package:intl/intl.dart';
import 'package:tracker/insights/after_event.dart';

String _percent(double share, String locale) =>
    NumberFormat.percentPattern(locale).format(share);

String _points(double fraction, String locale) =>
    NumberFormat.decimalPattern(locale).format((fraction * 100).round());

/// The findings among [results], largest difference first.
List<AfterEvent> afterEventCards(List<AfterEvent> results) =>
    results.where((a) => a.found).toList()..sort((a, b) {
      final int bySize = b.effect!.abs().compareTo(a.effect!.abs());
      return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
    });

/// "In the hour after a calendar event ends, you log Coffee 64% of the time,
/// against 21% at the same time on nearby days without one."
String afterEventSentence(AfterEvent finding, String habit, String locale) =>
    'In the hour after a calendar event ends, you log $habit '
    '${_percent(finding.eventRate, locale)} of the time, against '
    '${_percent(finding.controlRate, locale)} at the same time on nearby '
    'days without one.';

/// "Range: 30 to 52 points more often"; both ends share a sign.
String afterEventRange(AfterEvent finding, String locale) {
  final double low = finding.interval!.low, high = finding.interval!.high;
  final bool more = finding.effect! > 0;
  final (double near, double far) = more ? (low, high) : (-high, -low);
  return 'Range: ${_points(near, locale)} to ${_points(far, locale)} points '
      '${more ? 'more' : 'less'} often';
}

/// "From 42 days with calendar events, against the same times on 38 nearby
/// days with none".
String afterEventBasis(AfterEvent finding) =>
    'From ${finding.eventDays} days with calendar events, against the same '
    'times on ${finding.controlDays} nearby days clear of events';

/// [finding] as the lines "Copy as text" writes.
List<String> afterEventText(AfterEvent finding, String habit, String locale) =>
    <String>[
      habit,
      afterEventSentence(finding, habit, locale),
      afterEventRange(finding, locale),
      afterEventBasis(finding),
    ];
