import 'package:intl/intl.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/day_tags.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';

/// One habit's found day tags, the largest difference first, each joined to
/// the entry trigger card's finding for the same tag or area where it points
/// the same way.
class DayTagCard {
  const DayTagCard({
    required this.habit,
    required this.found,
    this.byEntry = const <String, TriggerAmount>{},
  });

  final HabitDayTags habit;
  final List<DayTagAmount> found;

  /// By [DayTagAmount.tag]: the entry finding said on this card instead of
  /// its own.
  final Map<String, TriggerAmount> byEntry;

  String get habitId => habit.habitId;
  DayTagAmount get headline => found.first;
  TriggerAmount? get headlineByEntry => byEntry[headline.tag];
}

double _size(DayTagAmount t) =>
    t.withoutMean == 0 ? double.infinity : (t.effect! / t.withoutMean).abs();

/// A card for each habit in [dayTags] with a found day tag, by the largest
/// difference, and [entries] (from [triggerCards]) less each finding joined
/// to one: a day tag and an entry tag often say the same thing, and two
/// cards for it would read as two findings.
({List<DayTagCard> days, List<TriggerCard> entries}) dayTagCards(
  List<HabitDayTags> dayTags,
  List<TriggerCard> entries,
) {
  int larger(DayTagAmount a, DayTagAmount b) {
    final int bySize = _size(b).compareTo(_size(a));
    return bySize != 0 ? bySize : a.tag.compareTo(b.tag);
  }

  final Map<String, TriggerCard> entryOf = <String, TriggerCard>{
    for (final TriggerCard c in entries) c.habitId: c,
  };
  final Map<String, Set<TriggerAmount>> joined = <String, Set<TriggerAmount>>{};
  final List<DayTagCard> days = <DayTagCard>[];
  for (final HabitDayTags h in dayTags) {
    final List<DayTagAmount> found = <DayTagAmount>[
      for (final DayTagAmount t in h.tags)
        if (t.found) t,
    ]..sort(larger);
    if (found.isEmpty) continue;
    final Map<String, TriggerAmount> byEntry = <String, TriggerAmount>{
      for (final DayTagAmount t in found)
        if (entryOf[h.habitId]?.found.where(
              (TriggerAmount e) =>
                  e.trigger == t.tag && e.relative.sign == t.effect!.sign,
            )
            case final Iterable<TriggerAmount> same when same.isNotEmpty)
          t.tag: same.first,
    };
    joined[h.habitId] = byEntry.values.toSet();
    days.add(DayTagCard(habit: h, found: found, byEntry: byEntry));
  }
  days.sort((DayTagCard a, DayTagCard b) {
    final int bySize = larger(a.headline, b.headline);
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
  return (
    days: days,
    entries: <TriggerCard>[
      for (final TriggerCard c in entries)
        if (<TriggerAmount>[
              for (final TriggerAmount t in c.found)
                if (!(joined[c.habitId]?.contains(t) ?? false)) t,
            ]
            case final List<TriggerAmount> rest when rest.isNotEmpty)
          TriggerCard(habit: c.habit, found: rest),
    ],
  );
}

String _number(double v, String locale) =>
    NumberFormat(v >= 10 ? '0' : '0.#', locale).format(v);

String _word(double v, Unit unit) => unit == Unit.time
    ? (v == 1 ? 'use' : 'uses')
    : unit.nameFor(double.parse(v.toStringAsFixed(v >= 10 ? 0 : 1)));

/// "On days you tagged Bad day, Wine came to 3.1 glasses against 1.8 on your
/// other tagged days." Says what goes together, never why.
String dayTagSentence(
  DayTagAmount t,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) =>
    'On days you tagged ${triggerDisplay(t.tag)}, $habit came to '
    '${_number(t.withMean, locale)} ${_word(t.withMean, unit)} against '
    '${_number(t.withoutMean, locale)} on your other tagged days.';

/// "Among the 48 days you tagged, of 130; Bad day is on 15 of them, each
/// weekday's usual amount held fixed". Tagging a day is optional, so only
/// tagged days are compared.
String dayTagBasis(HabitDayTags h, DayTagAmount t) =>
    'Among the ${h.tagged} days you tagged, of ${h.days}; '
    '${triggerDisplay(t.tag)} is on ${t.withDays} of them, each weekday’s '
    'usual amount held fixed';

/// "Days tagged Work or study: 2.4 against 1.6", with ", and by entry" when
/// the entry finding is joined to it.
String dayTagLine(DayTagAmount t, String locale, {bool byEntry = false}) =>
    'Days tagged ${triggerDisplay(t.tag)}: ${_number(t.withMean, locale)} '
    'against ${_number(t.withoutMean, locale)}${byEntry ? ', and by entry' : ''}';

/// The card's heading under the habit's name when its headline is joined.
const String dayTagJoined = 'By day and by entry';

/// [card] as the lines "Copy as text" writes.
List<String> dayTagText(
  DayTagCard card,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) => <String>[
  habit,
  if (card.headlineByEntry != null) dayTagJoined,
  dayTagSentence(card.headline, habit, locale, unit: unit),
  dayTagBasis(card.habit, card.headline),
  if (card.headlineByEntry case final TriggerAmount e)
    triggerSentence(e, habit),
  for (final DayTagAmount t in card.found.skip(1))
    dayTagLine(t, locale, byEntry: card.byEntry.containsKey(t.tag)),
];

/// Why [t] on [h] is not shown, led by the tag, as the entry triggers'
/// reasons are. Only tagged days are compared, so the count of them leads a
/// shortfall.
String dayTagRefusal(
  HabitDayTags h,
  DayTagAmount t, {
  InsightGates gates = const InsightGates(),
}) {
  final String tagged = '(${h.tagged} of ${h.days} days tagged)';
  final String reason = switch (t.refusal) {
    RefusalReason.tooFewDays when t.withDays < gates.minExposedDays =>
      'too few days with it yet: ${t.withDays} of ${gates.minExposedDays} '
          '$tagged',
    RefusalReason.tooFewDays when t.withoutDays < gates.minUnexposedDays =>
      'too few days tagged otherwise to compare: ${t.withoutDays} of '
          '${gates.minUnexposedDays} $tagged',
    RefusalReason.tooFewDays => 'too few tagged days yet to compare $tagged',
    RefusalReason.steadyAmount =>
      'the same total on every tagged day, so there’s no difference to '
          'compare',
    RefusalReason.uneven =>
      'they fall in too few months to tell from the time of year',
    RefusalReason.chance => 'could be chance, one of many comparisons',
    RefusalReason.tooSmall =>
      'too small to matter, under ${(dayTagFloor * 100).round()}% more or '
          'less than on your other tagged days',
    _ => 'within the noise, no clear difference',
  };
  return 'Days tagged ${triggerDisplay(t.tag)}: $reason';
}
