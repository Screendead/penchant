import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/insights/payoff_copy.dart';
import 'package:tracker/insights/replacement.dart';

/// "Around the same time, your logged amount of Vape rose from about 2 puffs
/// a day to 5, allowing for the trend it was already on."; with no entry
/// before, "Around the same time, your first entries for Vape appear: about
/// 5 puffs a day since.", since the journal cannot tell a habit taken up
/// from one newly logged. The habit's name only ever follows "of" or "for",
/// and nothing says one took the other's place.
String replacementSentence(
  Replacement r,
  String riser,
  String locale, {
  Unit unit = Unit.fallback,
}) => r.began
    ? 'Around the same time, your first entries for $riser appear: about '
          '${amountRates(r.since, 0, unit, locale)} since.'
    : 'Around the same time, your logged amount of $riser rose from about '
          '${amountRates(r.before, r.since, unit, locale)}, allowing for the '
          'trend it was already on.';

/// "Range: 1.2 to 2.9 more a day", the interval for the step; by the week
/// where [replacementSentence] reads by the week.
String replacementRange(Replacement r, String locale) {
  final bool weekly = max(r.before, r.since) < 1;
  String number(double v) => NumberFormat(
    v >= 10 ? '0' : '0.#',
    locale,
  ).format(v * (weekly ? 7 : 1));
  return 'Range: ${number(r.interval!.low)} to ${number(r.interval!.high)} '
      'more a ${weekly ? 'week' : 'day'}';
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
}) => r.began
    ? 'Also around then: first entries for $riser, about '
          '${amountRates(r.since, 0, unit, locale)} since'
    : 'Also around then: logged amount of $riser up from about '
          '${amountRates(r.before, r.since, unit, locale)}';

/// [card] as the lines "Copy as text" writes.
List<String> replacementText(
  ReplacementCard card,
  String Function(String id) nameOf,
  Unit Function(String id) unitOf,
  String locale,
) {
  final Replacement headline = card.risers.first;
  return <String>[
    nameOf(card.habitId),
    fallSentence(
      card.fall,
      nameOf(card.habitId),
      locale,
      unit: unitOf(card.habitId),
    ),
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
