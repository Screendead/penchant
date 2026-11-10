import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/recovery.dart';

/// What a recovery card is headed, after the habit's name.
const String recoveryLabel = 'after a heavy day';

/// One habit's recovery findings: the largest first night against its floor
/// leads.
class RecoveryCard {
  const RecoveryCard(this.headline, this.others);

  final Recovery headline;
  final List<Recovery> others;

  String get habitId => headline.habitId;
}

double _size(Recovery r) => r.nights.first.effect.abs() / r.floor!;

/// The findings among [results] as one card per habit, largest headline
/// first.
List<RecoveryCard> recoveryCards(List<Recovery> results) {
  final Map<String, List<Recovery>> byHabit = <String, List<Recovery>>{};
  for (final Recovery r in results) {
    if (r.found && metricCopy(r.metricId) != null) {
      byHabit.putIfAbsent(r.habitId, () => []).add(r);
    }
  }
  final List<RecoveryCard> cards = <RecoveryCard>[
    for (final List<Recovery> found in byHabit.values)
      () {
        final List<Recovery> sorted = found.toList()
          ..sort((a, b) => _size(b).compareTo(_size(a)));
        return RecoveryCard(sorted.first, sorted.sublist(1));
      }(),
  ];
  return cards..sort((a, b) {
    final int bySize = _size(b.headline).compareTo(_size(a.headline));
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
}

// "that night", "the second night", "the third night"; for a measure of the
// day, "the next day", "the second day after", "the third day after".
String _when(int night, {required bool ofNight}) {
  if (night == 1) return ofNight ? 'that night' : 'the next day';
  final String nth = switch (night) {
    2 => 'second',
    3 => 'third',
    _ => '${night}th',
  };
  return ofNight ? 'the $nth night' : 'the $nth day after';
}

// "21 min", rounded up at the digits shown so "within" stays true.
String _floorWords(Recovery r, String locale) {
  final MetricCopy copy = metricCopy(r.metricId)!;
  final double shown = r.floor! * copy.scale;
  int digits = copy.decimals;
  while (digits < 3 && shown < 0.5 * pow(10, -digits)) {
    digits++;
  }
  final num scale = pow(10, digits);
  final String number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format((shown * scale - 1e-9).ceil() / scale);
  return copy.unit.isEmpty ? number : '$number ${copy.unit}';
}

/// "After a day with 4 drinks or more logged for Beer, your time asleep
/// averages 31 min less that night and 16 min less the second night. By the
/// third night it is back within 21 min of your usual." Without a night
/// shown to be back, it ends "When it comes back to your usual isn’t clear
/// yet." The habit's name only ever follows "for", as in [findingSentence].
String recoverySentence(
  Recovery finding,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final List<String> parts = <String>[
    for (int k = 1; k <= max(1, finding.offNights); k++)
      '${findingChange(finding.nightFinding(k), locale)} '
          '${_when(k, ofNight: copy.night)}',
  ];
  final String changes = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  final String back = switch (finding.backBy) {
    final int night =>
      'By ${_when(night, ofNight: copy.night)} it is back within '
          '${_floorWords(finding, locale)} of your usual.',
    null => 'When it comes back to your usual isn’t clear yet.',
  };
  return 'After a day with ${cutAmount(finding.cut!, unit, locale)} or more '
      'logged for $habit, your ${copy.name} averages $changes. $back';
}

/// A card's line under its headline: "After a day with 4 drinks or more:
/// resting heart rate 3.0 bpm higher the next day, back by the second day
/// after".
String recoveryLine(
  Recovery finding,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final int off = finding.offNights;
  final String tail = switch (finding.backBy) {
    final int night => 'back by ${_when(night, ofNight: copy.night)}',
    null when off > 1 => 'still off ${_when(off, ofNight: copy.night)}',
    null => 'not clear yet when it comes back',
  };
  return 'After a day with ${cutAmount(finding.cut!, unit, locale)} or more: '
      '${copy.name} ${findingChange(finding.nightFinding(1), locale)} '
      '${_when(1, ofNight: copy.night)}, $tail';
}

/// "From 118 nights, 14 of them straight after a day with 4 drinks or more".
String recoveryBasis(
  Recovery finding, {
  String locale = 'en',
  Unit unit = Unit.fallback,
}) {
  final bool ofNight = metricCopy(finding.metricId)!.night;
  return 'From ${finding.usableDays} ${ofNight ? 'nights' : 'days'}, '
      '${finding.heavyDays} of them straight after a day with '
      '${cutAmount(finding.cut!, unit, locale)} or more';
}

/// "Range that night: 12 to 50 min less".
String recoveryRange(Recovery finding, String locale) {
  final bool ofNight = metricCopy(finding.metricId)!.night;
  return findingRange(finding.nightFinding(1), locale).replaceFirst(
    'Range:',
    'Range ${_when(1, ofNight: ofNight)}:',
  );
}

/// [card] as the lines "Copy as text" writes.
List<String> recoveryText(
  RecoveryCard card,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) => <String>[
  '$habit · $recoveryLabel',
  recoverySentence(card.headline, habit, locale, unit: unit),
  recoveryRange(card.headline, locale),
  recoveryBasis(card.headline, locale: locale, unit: unit),
  for (final Recovery other in card.others)
    recoveryLine(other, locale, unit: unit),
];
