import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_tree.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/what_follows.dart' show InsightGates;

/// The smallest difference in the amount an entry holds, as a share of the
/// amount on the other tagged entries, worth showing.
const double triggerFloor = 0.2;

enum TriggerVerdict {
  /// Differs past the correction for many comparisons and [triggerFloor].
  found,

  /// Under [InsightGates.minExposedDays] days with the trigger tagged, or
  /// under [InsightGates.minUnexposedDays] with only other triggers tagged.
  tooFewDays,

  /// Every tagged entry holds the same amount, so nothing can differ.
  steadyAmount,

  /// No clear difference, or not past the correction.
  chance,

  /// Past the correction, by less than [triggerFloor].
  tooSmall,
}

/// The amount on a habit's entries tagged [trigger] against its other tagged
/// entries. Days are the unit: each day's entries of either kind give that
/// day one mean, so a day with many entries counts once.
class TriggerAmount {
  const TriggerAmount({
    required this.trigger,
    required this.entries,
    required this.withDays,
    required this.withoutDays,
    required this.withMean,
    required this.withoutMean,
    required this.pValue,
    this.verdict,
  });

  /// A [triggerTree] path, a top-level node's id alone for the whole area,
  /// or a free-text label as written.
  final String trigger;

  /// The habit's tagged entries holding [trigger].
  final int entries;
  final int withDays;
  final int withoutDays;

  /// The mean over days of each day's mean amount per entry.
  final double withMean;
  final double withoutMean;

  /// Two-sided, Welch's; null when the gates left nothing to test.
  final double? pValue;

  /// Null until [judgeTriggerAmounts] has run.
  final TriggerVerdict? verdict;

  /// The difference as a share of [withoutMean].
  double get relative =>
      withoutMean == 0 ? 0 : (withMean - withoutMean) / withoutMean;

  TriggerAmount _judged(TriggerVerdict verdict) => TriggerAmount(
    trigger: trigger,
    entries: entries,
    withDays: withDays,
    withoutDays: withoutDays,
    withMean: withMean,
    withoutMean: withoutMean,
    pValue: pValue,
    verdict: verdict,
  );
}

/// One habit's tagging and each trigger tagged on it.
class HabitTriggers {
  const HabitTriggers({
    required this.habitId,
    required this.entries,
    required this.tagged,
    required this.triggers,
  });

  final String habitId;

  /// Entries with a positive amount in the span read.
  final int entries;

  /// Those of [entries] with at least one trigger.
  final int tagged;

  /// Most entries first.
  final List<TriggerAmount> triggers;
}

/// What a stored trigger counts under: a tree path under its top-level node
/// and itself, a free-text label as itself.
Set<String> _keys(String stored) {
  final String trimmed = stored.trim();
  if (trimmed.isEmpty) return const <String>{};
  if (triggerLabels(trimmed) == null) return <String>{trimmed};
  final List<String> ids = trimmed.split(triggerPathSeparator);
  return <String>{
    for (int i = 1; i <= ids.length; i++)
      ids.sublist(0, i).join(triggerPathSeparator),
  };
}

/// Every habit in [uses] with a tagged entry, none in [skip], on days up to
/// and including [through]. Unjudged: pass the triggers to
/// [judgeTriggerAmounts].
///
/// Tagging is optional, so only tagged entries are compared: an untagged
/// entry says nothing about what went on. A top-level node that covers the
/// same entries as one path under it is left out, since it is the same
/// comparison.
List<HabitTriggers> triggerAmounts({
  required Iterable<HabitUse> uses,
  required DateTime through,
  Set<String> skip = const <String>{},
  InsightGates gates = const InsightGates(),
}) {
  final DateTime last = startOfDay(through);
  final Map<String, List<HabitUse>> byHabit = <String, List<HabitUse>>{};
  for (final HabitUse use in uses) {
    if (use.amount <= 0 || skip.contains(use.habitId)) continue;
    if (lateDayOf(use.at).isAfter(last)) continue;
    byHabit.putIfAbsent(use.habitId, () => <HabitUse>[]).add(use);
  }
  final List<String> ids = byHabit.keys.toList()..sort();
  return <HabitTriggers>[
    for (final String id in ids)
      if (_habit(id, byHabit[id]!, gates) case final HabitTriggers h) h,
  ];
}

HabitTriggers? _habit(String id, List<HabitUse> all, InsightGates gates) {
  final List<({DateTime day, double amount, Set<String> keys})> tagged =
      <({DateTime day, double amount, Set<String> keys})>[
        for (final HabitUse u in all)
          if (<String>{for (final String t in u.triggers) ..._keys(t)}
              case final Set<String> keys when keys.isNotEmpty)
            (day: lateDayOf(u.at), amount: u.amount.toDouble(), keys: keys),
      ];
  if (tagged.isEmpty) return null;
  final Map<String, Set<int>> holders = <String, Set<int>>{};
  for (final (int i, ({DateTime day, double amount, Set<String> keys}) e)
      in tagged.indexed) {
    for (final String k in e.keys) {
      holders.putIfAbsent(k, () => <int>{}).add(i);
    }
  }
  bool sameAsChild(String key) =>
      triggerLabels(key)?.length == 1 &&
      holders.entries.any(
        (MapEntry<String, Set<int>> other) =>
            other.key.startsWith('$key$triggerPathSeparator') &&
            other.value.length == holders[key]!.length &&
            other.value.containsAll(holders[key]!),
      );
  final bool steady = tagged.every((e) => e.amount == tagged.first.amount);
  final List<TriggerAmount> triggers = <TriggerAmount>[
    for (final MapEntry<String, Set<int>> h in holders.entries)
      if (!sameAsChild(h.key)) _trigger(h.key, h.value, tagged, steady, gates),
  ];
  triggers.sort((a, b) {
    final int byEntries = b.entries.compareTo(a.entries);
    return byEntries != 0 ? byEntries : a.trigger.compareTo(b.trigger);
  });
  return HabitTriggers(
    habitId: id,
    entries: all.length,
    tagged: tagged.length,
    triggers: triggers,
  );
}

TriggerAmount _trigger(
  String key,
  Set<int> holding,
  List<({DateTime day, double amount, Set<String> keys})> tagged,
  bool steady,
  InsightGates gates,
) {
  final Map<DateTime, List<double>> withByDay = <DateTime, List<double>>{};
  final Map<DateTime, List<double>> withoutByDay = <DateTime, List<double>>{};
  for (final (int i, ({DateTime day, double amount, Set<String> keys}) e)
      in tagged.indexed) {
    (holding.contains(i) ? withByDay : withoutByDay)
        .putIfAbsent(e.day, () => <double>[])
        .add(e.amount);
  }
  final List<double> x = <double>[
    for (final List<double> d in withByDay.values) mean(d),
  ];
  final List<double> y = <double>[
    for (final List<double> d in withoutByDay.values) mean(d),
  ];
  final bool enough =
      x.length >= gates.minExposedDays && y.length >= gates.minUnexposedDays;
  return TriggerAmount(
    trigger: key,
    entries: holding.length,
    withDays: x.length,
    withoutDays: y.length,
    withMean: x.isEmpty ? 0 : mean(x),
    withoutMean: y.isEmpty ? 0 : mean(y),
    pValue: enough && !steady ? _welchTwoSided(x, y) : null,
  );
}

double _welchTwoSided(List<double> x, List<double> y) {
  final double vx = sampleVariance(x) / x.length;
  final double vy = sampleVariance(y) / y.length;
  final double se = sqrt(vx + vy);
  final double difference = mean(x) - mean(y);
  if (se == 0) return difference == 0 ? 1 : 0;
  final double df =
      pow(vx + vy, 2) /
      (pow(vx, 2) / (x.length - 1) + pow(vy, 2) / (y.length - 1));
  return studentTTwoSided(difference / se, df);
}

/// [habits] with each trigger's verdict. A trigger is found only when it
/// passes Benjamini-Hochberg at [InsightGates.falseDiscoveryRate] in one
/// family with [alongside], the p-values of the report's other comparisons;
/// the size gate runs after, so it only hides.
List<HabitTriggers> judgeTriggerAmounts(
  List<HabitTriggers> habits, {
  List<double> alongside = const <double>[],
  InsightGates gates = const InsightGates(),
}) {
  final List<double> ps = <double>[
    for (final HabitTriggers h in habits)
      for (final TriggerAmount t in h.triggers) ?t.pValue,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    ...ps,
    ...alongside,
  ], gates.falseDiscoveryRate);
  int k = 0;
  return <HabitTriggers>[
    for (final HabitTriggers h in habits)
      HabitTriggers(
        habitId: h.habitId,
        entries: h.entries,
        tagged: h.tagged,
        triggers: <TriggerAmount>[
          for (final TriggerAmount t in h.triggers)
            t._judged(switch (t) {
              TriggerAmount(pValue: null)
                  when t.withDays < gates.minExposedDays ||
                      t.withoutDays < gates.minUnexposedDays =>
                TriggerVerdict.tooFewDays,
              TriggerAmount(pValue: null) => TriggerVerdict.steadyAmount,
              _ when !kept[k++] => TriggerVerdict.chance,
              _ when t.relative.abs() < triggerFloor => TriggerVerdict.tooSmall,
              _ => TriggerVerdict.found,
            }),
        ],
      ),
  ];
}

/// The p-values [judgeTriggerAmounts] tests, for the page's family.
List<double> triggerPValues(List<HabitTriggers> habits) => <double>[
  for (final HabitTriggers h in habits)
    for (final TriggerAmount t in h.triggers) ?t.pValue,
];

/// One habit's found triggers, the largest difference first.
class TriggerCard {
  const TriggerCard({required this.habit, required this.found});

  final HabitTriggers habit;
  final List<TriggerAmount> found;

  String get habitId => habit.habitId;
  TriggerAmount get headline => found.first;
}

/// A card for each habit in [judged] with a found trigger, by the largest
/// difference.
List<TriggerCard> triggerCards(List<HabitTriggers> judged) {
  int larger(TriggerAmount a, TriggerAmount b) {
    final int bySize = b.relative.abs().compareTo(a.relative.abs());
    return bySize != 0 ? bySize : a.trigger.compareTo(b.trigger);
  }

  final List<TriggerCard> cards = <TriggerCard>[
    for (final HabitTriggers h in judged)
      if (<TriggerAmount>[
            for (final TriggerAmount t in h.triggers)
              if (t.verdict == TriggerVerdict.found) t,
          ]
          case final List<TriggerAmount> found when found.isNotEmpty)
        TriggerCard(habit: h, found: found..sort(larger)),
  ];
  return cards..sort((TriggerCard a, TriggerCard b) {
    final int bySize = larger(a.headline, b.headline);
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
}

String _percent(double share) => '${(share * 100).round()}%';

String _amount(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);

String _direction(TriggerAmount t) =>
    '${_percent(t.relative.abs())} ${t.relative > 0 ? 'more' : 'less'}';

/// "Entries of Cigarettes you tagged Social › Friends hold 45% more than your
/// other tagged ones: 2.9 against 2 on average." Says what goes together,
/// never why.
String triggerSentence(TriggerAmount t, String habit) =>
    'Entries of $habit you tagged ${triggerDisplay(t.trigger)} hold '
    '${_direction(t)} than your other tagged ones: ${_amount(t.withMean)} '
    'against ${_amount(t.withoutMean)} on average.';

/// "Among the 64 entries you tagged, of 120; Social › Friends is on 30 of
/// them, over 18 days". Tagging is optional, so only tagged entries are
/// compared.
String triggerBasis(HabitTriggers h, TriggerAmount t) =>
    'Among the ${h.tagged} entries you tagged, of ${h.entries}; '
    '${triggerDisplay(t.trigger)} is on ${t.entries} of them, over '
    '${t.withDays} days';

/// "Tagged Work: 30% less".
String triggerLine(TriggerAmount t) =>
    'Tagged ${triggerDisplay(t.trigger)}: ${_direction(t)}';

/// A card as plain lines, for the copied text.
List<String> triggerText(TriggerCard card, String habit) => <String>[
  habit,
  triggerSentence(card.headline, habit),
  triggerBasis(card.habit, card.headline),
  for (final TriggerAmount t in card.found.skip(1)) triggerLine(t),
];
