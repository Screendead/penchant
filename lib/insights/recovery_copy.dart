import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/what_follows.dart';

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

/// Each finding among [results] on the habit and measure of a line in the
/// amount on one of [cards], by that line's habit and measure; the rest stay
/// for [recoveryCards].
({Map<(String, String), Recovery> joined, List<Recovery> rest}) joinRecovery(
  List<InsightCard> cards,
  List<Recovery> results,
) {
  final Set<(String, String)> lines = <(String, String)>{
    for (final InsightCard card in cards)
      for (final HabitFinding f in <HabitFinding>[
        card.headline,
        ...card.others,
      ])
        if (f.kind == InsightKind.doseLine) (f.habitId, f.metricId),
  };
  final Map<(String, String), Recovery> joined = <(String, String), Recovery>{};
  final List<Recovery> rest = <Recovery>[];
  for (final Recovery r in results) {
    if (r.found &&
        metricCopy(r.metricId) != null &&
        lines.contains((r.habitId, r.metricId))) {
      joined[(r.habitId, r.metricId)] = r;
    } else {
      rest.add(r);
    }
  }
  return (joined: joined, rest: rest);
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
/// averages 31 min less than your usual that night and 16 min less the second
/// night. By the
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
  return 'After a day with ${cutAmount(finding.cut!, unit, locale)} or more '
      'logged for $habit, your ${copy.name} averages '
      '${_changes(finding, locale)}. ${_back(finding, locale)}';
}

// "31 min less than your usual that night and 16 min less the second night".
String _changes(Recovery finding, String locale) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final List<String> parts = <String>[
    for (int k = 1; k <= max(1, finding.offNights); k++)
      '${findingChange(finding.nightFinding(k), locale)}'
          '${k == 1 ? ' than your usual' : ''} '
          '${_when(k, ofNight: copy.night)}',
  ];
  return parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

String _back(Recovery finding, String locale) => switch (finding.backBy) {
  final int night when metricCopy(finding.metricId)!.inWords =>
    'By ${_when(night, ofNight: false)} it is back to your usual, within '
        'half its usual day-to-day swing.',
  final int night =>
    'By ${_when(night, ofNight: metricCopy(finding.metricId)!.night)} it is '
        'back within ${_floorWords(finding, locale)} of your usual.',
  null => 'When it comes back to your usual isn’t clear yet.',
};

// "after such a day" when [finding]'s heavy day is [line]'s side of the
// line, else the heavy day in full.
String _afterSuch(
  Recovery finding,
  HabitFinding line,
  String locale,
  Unit unit,
) => finding.cut == line.cut
    ? 'after such a day'
    : 'after a day with ${cutAmount(finding.cut!, unit, locale)} or more';

/// [line], a line in the amount on [finding]'s habit and measure, with
/// [finding] after it, so the heavy day is said once: "On days with 4 drinks
/// or more logged for Beer, your time asleep that night averages 25 min less
/// than on days with fewer; after such a day it averages 31 min less than
/// your usual that night. By the second night it is back within 21 min of your usual."
String recoveryJoinedSentence(
  HabitFinding line,
  Recovery finding,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String first = findingSentence(line, habit, locale, unit: unit);
  return '${first.substring(0, first.length - 1)}; '
      '${_afterSuch(finding, line, locale, unit)} it averages '
      '${_changes(finding, locale)}. ${_back(finding, locale)}';
}

/// [line]'s line under a headline with [finding] after it: "From 4 drinks a
/// day: time asleep 25 min less; after such a day 31 min less that night,
/// back by the second night".
String recoveryJoinedLine(
  HabitFinding line,
  Recovery finding,
  String locale, {
  Unit unit = Unit.fallback,
}) =>
    '${findingLine(line, locale, unit: unit)}; '
    '${_afterSuch(finding, line, locale, unit)} '
    '${findingChange(finding.nightFinding(1), locale)} '
    '${_when(1, ofNight: metricCopy(finding.metricId)!.night)}, '
    '${_tail(finding)}';

/// "From 118 nights, 14 of them straight after such a day", under a joined
/// headline; the heavy day in full when it is not [line]'s.
String recoveryJoinedBasis(
  HabitFinding line,
  Recovery finding, {
  String locale = 'en',
  Unit unit = Unit.fallback,
}) {
  final bool ofNight = metricCopy(finding.metricId)!.night;
  return 'From ${finding.usableDays} ${ofNight ? 'nights' : 'days'}, '
      '${finding.heavyDays} of them straight '
      '${_afterSuch(finding, line, locale, unit)}';
}

String _tail(Recovery finding) {
  final bool ofNight = metricCopy(finding.metricId)!.night;
  final int off = finding.offNights;
  return switch (finding.backBy) {
    final int night => 'back by ${_when(night, ofNight: ofNight)}',
    null when off > 1 => 'still off ${_when(off, ofNight: ofNight)}',
    null => 'not clear yet when it comes back',
  };
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
  return 'After a day with ${cutAmount(finding.cut!, unit, locale)} or more: '
      '${copy.name} ${findingChange(finding.nightFinding(1), locale)} '
      '${_when(1, ofNight: copy.night)}, ${_tail(finding)}';
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

/// "Range that night: 12 to 50 min less"; [joined], under a line in the
/// amount that has a "Range:" of its own, "Range against your usual that
/// night: 12 to 50 min less".
String recoveryRange(Recovery finding, String locale, {bool joined = false}) {
  final bool ofNight = metricCopy(finding.metricId)!.night;
  return findingRange(finding.nightFinding(1), locale).replaceFirst(
    'Range:',
    'Range ${joined ? 'against your usual ' : ''}${_when(1, ofNight: ofNight)}:',
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
