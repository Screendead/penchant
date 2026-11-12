import 'package:intl/intl.dart';
import 'package:tracker/insights/places.dart';

String _percent(double share, String locale) =>
    NumberFormat.percentPattern(locale).format(share);

String _points(double fraction, String locale) =>
    NumberFormat.decimalPattern(locale).format((fraction * 100).round());

/// The findings among [results], largest difference first.
List<AtPlace> atPlaceCards(List<AtPlace> results) =>
    results.where((a) => a.found).toList()..sort((a, b) {
      final int bySize = b.effect!.abs().compareTo(a.effect!.abs());
      if (bySize != 0) return bySize;
      final int byHabit = a.habitId.compareTo(b.habitId);
      return byHabit != 0 ? byHabit : a.placeId.compareTo(b.placeId);
    });

/// "On days you spend time at Place 1, you log 62% of your waking Coffee
/// entries there, though you spend 35% of those hours there."
String atPlaceSentence(
  AtPlace finding,
  String habit,
  String place,
  String locale,
) =>
    'On days you spend time at $place, you log '
    '${_percent(finding.useShare, locale)} of your waking $habit entries '
    'there, though you spend ${_percent(finding.timeShare, locale)} of those '
    'hours there.';

/// "Range: 18 to 36 points more than its share of time"; both ends share a
/// sign.
String atPlaceRange(AtPlace finding, String locale) {
  final double low = finding.interval!.low, high = finding.interval!.high;
  final bool more = finding.effect! > 0;
  final (double near, double far) = more ? (low, high) : (-high, -low);
  return 'Range: ${_points(near, locale)} to ${_points(far, locale)} points '
      '${more ? 'more' : 'less'} than its share of your time';
}

/// "From 31 days with time both there and elsewhere, 7:00 to 23:00".
String atPlaceBasis(AtPlace finding) =>
    'From ${finding.days} days with time both there and elsewhere, '
    '$placeWakingFromHour:00 to $placeWakingToHour:00';

/// [finding] as the lines "Copy as text" writes.
List<String> atPlaceText(
  AtPlace finding,
  String habit,
  String place,
  String locale,
) => <String>[
  habit,
  atPlaceSentence(finding, habit, place, locale),
  atPlaceRange(finding, locale),
  atPlaceBasis(finding),
];
