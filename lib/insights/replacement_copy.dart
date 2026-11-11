import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/replacement.dart';

String _weeks(int days) {
  final int weeks = (days / 7).round();
  return weeks == 1 ? 'week' : '$weeks weeks';
}

/// "Around the same time, your logged amount of Vape rose from about 2 puffs
/// a day to 5."; with no entry ever before, "Around the same time, your
/// first entries for Vape appear: about 5 puffs a day since.", since the
/// journal cannot tell a habit taken up from one newly logged; with none in
/// the baseline but some earlier, "your entries for Vape start again after
/// none in the 13 weeks before". The habit's name only ever follows "of" or
/// "for", and nothing says one took the other's place.
String replacementSentence(
  Replacement r,
  String riser,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String since = 'about ${amountRates(r.since, 0, unit, locale)} since.';
  if (r.began) {
    return 'Around the same time, your first entries for $riser appear: '
        '$since';
  }
  if (r.resumed) {
    return 'Around the same time, your entries for $riser start again after '
        'none in the ${_weeks(r.baselineDays)} before: $since';
  }
  return 'Around the same time, your logged amount of $riser rose from about '
      '${amountRates(r.before, r.since, unit, locale)}.';
}

/// "Range: 1.2 to 2.9 more a day, allowing for the trend it was already on",
/// the interval for the step, which the sentence's plain averages are not;
/// by the week where [replacementSentence] reads by the week.
String replacementRange(Replacement r, String locale) {
  final bool weekly = max(r.before, r.since) < 1;
  String number(double v) =>
      NumberFormat(v >= 10 ? '0' : '0.#', locale).format(v * (weekly ? 7 : 1));
  return 'Range: ${number(r.interval!.low)} to ${number(r.interval!.high)} '
      'more a ${weekly ? 'week' : 'day'}, allowing for the trend it was '
      'already on';
}

/// "From 91 days before and 60 since".
String replacementBasis(Replacement r) =>
    'From ${r.baselineDays} days before and ${r.sinceDays} since';

/// What the card cannot say, under every finding.
const String replacementCaveat =
    'Both are what your entries show. Moving at the same time does not mean '
    'one took the other’s place.';

/// A card's line under its headline: "Also around then: logged amount of Tea
/// up from about 1 cup a day to 2".
String replacementLine(
  Replacement r,
  String riser,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String since = 'about ${amountRates(r.since, 0, unit, locale)} since';
  if (r.began) return 'Also around then: first entries for $riser, $since';
  if (r.resumed) return 'Also around then: entries for $riser again, $since';
  return 'Also around then: logged amount of $riser up from about '
      '${amountRates(r.before, r.since, unit, locale)}';
}

/// [card] as the lines "Copy as text" writes.
List<String> replacementText(
  ReplacementCard card,
  String Function(String id) nameOf,
  Unit Function(String id) unitOf,
  String locale,
) => <String>[
  nameOf(card.habitId),
  fallSentence(
    card.fall,
    nameOf(card.habitId),
    locale,
    unit: unitOf(card.habitId),
  ),
  ...replacementRiserText(card, nameOf, unitOf, locale),
];

/// [card]'s lines after the fall, for text that has already stated it.
List<String> replacementRiserText(
  ReplacementCard card,
  String Function(String id) nameOf,
  Unit Function(String id) unitOf,
  String locale,
) {
  final Replacement headline = card.risers.first;
  return <String>[
    replacementSentence(
      headline,
      nameOf(headline.riserId),
      locale,
      unit: unitOf(headline.riserId),
    ),
    replacementRange(headline, locale),
    replacementBasis(headline),
    for (final Replacement other in card.risers.skip(1))
      replacementLine(
        other,
        nameOf(other.riserId),
        locale,
        unit: unitOf(other.riserId),
      ),
    replacementCaveat,
  ];
}
