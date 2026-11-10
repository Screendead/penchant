import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

/// One habit's findings of what comes before it: the largest by
/// [practicalSize] leads.
class BeforeUseCard {
  const BeforeUseCard(this.headline, this.others);

  final BeforeUse headline;
  final List<BeforeUse> others;

  String get habitId => headline.habitId;
}

/// The findings among [results] as one card per habit, largest headline
/// first.
List<BeforeUseCard> beforeUseCards(
  List<BeforeUse> results, {
  Map<String, double> floors = const <String, double>{},
}) {
  double size(BeforeUse b) => practicalSize(b.asFinding, floors: floors);
  final Map<String, List<BeforeUse>> byHabit = <String, List<BeforeUse>>{};
  for (final BeforeUse b in results) {
    if (b.found && metricCopy(b.metricId) != null) {
      byHabit.putIfAbsent(b.habitId, () => []).add(b);
    }
  }
  final List<BeforeUseCard> cards = <BeforeUseCard>[
    for (final List<BeforeUse> found in byHabit.values)
      () {
        final List<BeforeUse> sorted = found.toList()
          ..sort((a, b) => size(b).compareTo(size(a)));
        return BeforeUseCard(sorted.first, sorted.sublist(1));
      }(),
  ];
  return cards..sort((a, b) {
    final int bySize = size(b.headline).compareTo(size(a.headline));
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
}

String _lead(BeforeUse b) =>
    metricCopy(b.metricId)!.night ? 'The night before' : 'The day before';

bool _atSameWaking(BeforeUse b) =>
    b.kind == BeforeUseKind.firstUse && sleepMinutesIds.contains(b.metricId);

/// "The night before a day with Coffee, your time asleep averages 24 min
/// less than before a day without it." The habit's name only ever follows
/// "with", "for", "of" or "before", as in [findingSentence].
String beforeUseSentence(
  BeforeUse finding,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String name = metricCopy(finding.metricId)!.name;
  final String change = findingChange(finding.asFinding, locale);
  final String lead = _lead(finding);
  return switch (finding.kind) {
    BeforeUseKind.whether =>
      '$lead a day with $habit, your $name averages $change than before a '
          'day without it.',
    BeforeUseKind.amount =>
      '$lead a day with '
          '${stepWords(finding.step, unit, locale, more: true)} logged for '
          '$habit, your $name averages $change.',
    BeforeUseKind.firstUse =>
      '$lead a day your first use of $habit comes an hour earlier, your '
          '$name averages $change'
          '${_atSameWaking(finding) ? ', at the same waking time' : ''}.',
    BeforeUseKind.hourBefore =>
      'In the hour before $habit, your $name averages $change than in the '
          'same hour after waking on nearby days without it.',
  };
}

/// A card's line under its headline.
String beforeUseLine(
  BeforeUse finding,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String change =
      '${metricCopy(finding.metricId)!.name} '
      '${findingChange(finding.asFinding, locale)}';
  return switch (finding.kind) {
    BeforeUseKind.whether => '${_lead(finding)} a day with it: $change',
    BeforeUseKind.amount =>
      'Before a day with more, per extra '
          '${stepWords(finding.step, unit, locale)}: $change',
    BeforeUseKind.firstUse =>
      'Before an earlier first use: $change per hour'
          '${_atSameWaking(finding) ? ', at the same waking time' : ''}',
    BeforeUseKind.hourBefore => 'In the hour before it: $change',
  };
}

/// "From 64 days, 22 of them with Coffee".
String beforeUseBasis(BeforeUse finding, String habit) =>
    switch (finding.kind) {
      BeforeUseKind.whether =>
        'From ${finding.usableDays} days, ${finding.exposedDays} of them '
            'with $habit',
      BeforeUseKind.amount ||
      BeforeUseKind.firstUse => 'From ${finding.usableDays} days with $habit',
      BeforeUseKind.hourBefore =>
        'From ${finding.exposedDays} days with $habit, against '
            '${finding.usableDays - finding.exposedDays} days at the same '
            'time after waking with none of it within '
            '${hoursAfterClearMinutes ~/ 60} hours',
    };

/// [card] as the lines "Copy as text" writes.
List<String> beforeUseText(
  BeforeUseCard card,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) => <String>[
  habit,
  beforeUseSentence(card.headline, habit, locale, unit: unit),
  findingRange(card.headline.asFinding, locale),
  beforeUseBasis(card.headline, habit),
  for (final BeforeUse other in card.others)
    beforeUseLine(other, locale, unit: unit),
];
