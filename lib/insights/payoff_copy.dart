import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/payoff.dart';

/// One habit's fall and what moved since: the largest finding by
/// [practicalSize] leads [findings]; with none, [refusal] is why.
class PayoffCard {
  const PayoffCard(this.fall, this.findings, this.refusal);

  final HabitFall fall;
  final List<Payoff> findings;
  final Payoff? refusal;

  String get habitId => fall.habitId;
}

int _rank(PayoffRefusal reason) => switch (reason) {
  PayoffRefusal.tooSmall => 0,
  PayoffRefusal.otherFall => 1,
  PayoffRefusal.chance => 2,
  PayoffRefusal.alreadyMoving => 3,
  PayoffRefusal.withinNoise => 4,
  PayoffRefusal.tooFewDays => 5,
};

/// [results] as one card per habit: those with a finding first, largest
/// headline first, then the rest by habit.
List<PayoffCard> payoffCards(
  List<Payoff> results, {
  Map<String, double> floors = const <String, double>{},
}) {
  double size(Payoff p) => practicalSize(p.asFinding, floors: floors);
  final Map<String, List<Payoff>> byHabit = <String, List<Payoff>>{};
  for (final Payoff p in results) {
    if (metricCopy(p.metricId) != null) {
      byHabit.putIfAbsent(p.habitId, () => []).add(p);
    }
  }
  final List<PayoffCard> cards = <PayoffCard>[
    for (final List<Payoff> all in byHabit.values)
      () {
        final List<Payoff> found = all.where((p) => p.found).toList()
          ..sort((a, b) => size(b).compareTo(size(a)));
        return PayoffCard(
          all.first.fall,
          found,
          found.isNotEmpty
              ? null
              : all.reduce(
                  (a, b) => _rank(b.refusal!) < _rank(a.refusal!) ? b : a,
                ),
        );
      }(),
  ];
  return cards..sort((a, b) {
    if (a.findings.isEmpty != b.findings.isEmpty) {
      return a.findings.isEmpty ? 1 : -1;
    }
    if (a.findings.isNotEmpty) {
      final int bySize = size(
        b.findings.first,
      ).compareTo(size(a.findings.first));
      if (bySize != 0) return bySize;
    }
    return a.habitId.compareTo(b.habitId);
  });
}

/// "4 drinks a day to 1.5"; with [since] zero, "4 drinks a day". When
/// neither reaches one a day, both read by the week.
String amountRates(double before, double since, Unit unit, String locale) {
  final bool weekly = max(before, since) < 1;
  final double from = before * (weekly ? 7 : 1);
  final double to = since * (weekly ? 7 : 1);
  String number(double v) =>
      NumberFormat(v >= 10 ? '0' : '0.#', locale).format(v);
  final double shown = double.parse(from.toStringAsFixed(from >= 10 ? 0 : 1));
  final String word = unit == Unit.time
      ? pluralWord(shown, one: 'use', other: 'uses')
      : unit.nameFor(shown);
  final String first = '${number(from)} $word a ${weekly ? 'week' : 'day'}';
  return since == 0 ? first : '$first to ${number(to)}';
}

/// "Your logged amount of Coffee fell from about 4 drinks a day to 1.5
/// around March 3, 2026."; with no entry since, "No entries for Coffee since
/// March 3, 2026, from about 4 drinks a day before.", since the journal cannot
/// tell a habit given up from one no longer logged. The habit's name only
/// ever follows "of" or "for", as in [findingSentence].
String fallSentence(
  HabitFall fall,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final String date = formatDate(fall.day);
  final String rates = amountRates(fall.before, fall.since, unit, locale);
  return fall.stopped
      ? 'No entries for $habit since $date, from about $rates before.'
      : 'Your logged amount of $habit fell from about $rates around $date.';
}

String _weeks(int days) {
  final int weeks = (days / 7).round();
  return weeks == 1 ? 'week' : '$weeks weeks';
}

/// "Since then, your resting heart rate averages 2.1 bpm lower than in the
/// 13 weeks before, allowing for the trend it was already on."
String payoffSentence(
  Payoff finding,
  String locale, {
  PayoffGates gates = const PayoffGates(),
}) {
  final String name = metricCopy(finding.metricId)!.name;
  final String change = findingChange(finding.asFinding, locale);
  final String lead = finding.capped
      ? 'In the ${_weeks(gates.sinceDays)} after'
      : 'Since then';
  final int baseline = finding.fall.day.difference(finding.fall.from).inHours;
  return '$lead, your $name averages $change than in the '
      '${_weeks((baseline / 24).round())} before, allowing for the trend it '
      'was already on.';
}

/// A card's line under its headline: "time asleep 24 min more".
String payoffLine(Payoff finding, String locale) =>
    'Also since: ${metricCopy(finding.metricId)!.name} '
    '${findingChange(finding.asFinding, locale)}';

/// "From 88 nights before and 41 since".
String payoffBasis(Payoff finding) {
  final String unit = metricCopy(finding.metricId)!.night ? 'nights' : 'days';
  return 'From ${finding.baselineValues} $unit before and '
      '${finding.sinceValues} since';
}

/// Why a fall has no finding, in plain words. The other habit of
/// [PayoffRefusal.otherFall] goes unnamed: it may be archived.
String payoffRefusal(Payoff refused) => switch (refused.refusal!) {
  PayoffRefusal.tooFewDays =>
    'Too few days of Apple Health on each side of it to compare yet.',
  PayoffRefusal.otherFall =>
    'Another habit’s logged amount fell within two weeks of it, so what '
        'moved since can’t be put down to either.',
  PayoffRefusal.withinNoise =>
    'No clear difference in your sleep, heart or activity since: within '
        'the noise.',
  PayoffRefusal.alreadyMoving =>
    'Your ${metricCopy(refused.metricId)!.name} was already shifting '
        'before it, so the change since can’t be told apart from that.',
  PayoffRefusal.chance =>
    'What moved since could be chance: one of many comparisons.',
  PayoffRefusal.tooSmall => 'What moved since is too small to matter.',
};

/// [card] as the lines "Copy as text" writes.
List<String> payoffText(
  PayoffCard card,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) => <String>[
  habit,
  fallSentence(card.fall, habit, locale, unit: unit),
  if (card.refusal case final Payoff refused) payoffRefusal(refused),
  if (card.findings.isNotEmpty) ...<String>[
    payoffSentence(card.findings.first, locale),
    findingRange(card.findings.first.asFinding, locale),
    payoffBasis(card.findings.first),
    for (final Payoff other in card.findings.skip(1)) payoffLine(other, locale),
  ],
];
