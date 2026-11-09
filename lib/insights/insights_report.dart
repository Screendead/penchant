import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/what_follows.dart';

/// The earliest day an entry can be dated (the date picker's floor), so the
/// journal query misses none.
final DateTime insightsJournalStart = DateTime(2000);

/// HealthKit shipped with iOS 8 in September 2014; reading from there spares a
/// call for each empty year before it.
final DateTime insightsHealthStart = DateTime(2014, 9);

/// The days Insights reads: every day up to and including [today]. Keyed on
/// the day alone, so a provider keyed on it stays put until the day changes.
({DateTime start, DateTime end}) insightsRange(DateTime today) =>
    (start: insightsJournalStart, end: addDays(startOfDay(today), 1));

/// The Health read for [range], a calendar year per call at most, oldest
/// first.
List<({DateTime start, DateTime end})> insightsHealthChunks(
  ({DateTime start, DateTime end}) range,
) {
  final List<({DateTime start, DateTime end})> chunks =
      <({DateTime start, DateTime end})>[];
  DateTime start = range.start.isBefore(insightsHealthStart)
      ? insightsHealthStart
      : startOfDay(range.start);
  while (start.isBefore(range.end)) {
    final DateTime next = DateTime(start.year + 1);
    final DateTime end = next.isBefore(range.end) ? next : range.end;
    chunks.add((start: start, end: end));
    start = end;
  }
  return chunks;
}

/// The local day of each vice's first entry, by vice ID.
Map<String, DateTime> insightsFirstDays(Iterable<ViceActivity> activities) {
  final Map<String, DateTime> first = <String, DateTime>{};
  for (final ViceActivity a in activities) {
    final DateTime at = a.createdAt.toDate();
    final DateTime? seen = first[a.viceID];
    if (seen == null || at.isBefore(seen)) first[a.viceID] = at;
  }
  return <String, DateTime>{
    for (final MapEntry<String, DateTime> e in first.entries)
      e.key: startOfDay(e.value),
  };
}

/// The earliest of [firstDays] among the vices [keep] accepts; null with none.
DateTime? insightsFirstDay(
  Map<String, DateTime> firstDays,
  bool Function(String viceID) keep,
) {
  DateTime? first;
  for (final MapEntry<String, DateTime> e in firstDays.entries) {
    if (keep(e.key) && (first == null || e.value.isBefore(first))) {
      first = e.value;
    }
  }
  return first;
}

/// What the engine runs on. Sendable to another isolate.
class InsightsInput {
  const InsightsInput({
    required this.uses,
    required this.outcomes,
    required this.from,
    required this.through,
  });

  factory InsightsInput.from({
    required Iterable<ViceActivity> activities,
    required Iterable<hs.DailyOutcome> health,
    required DateTime today,
  }) {
    final ({DateTime start, DateTime end}) range = insightsRange(today);
    final DateTime unfinished = startOfDay(today);
    return InsightsInput(
      // A locked entry counts: its vice and quantity are plaintext.
      uses: habitUsesFrom(activities).toList(),
      outcomes: <DailyOutcome>[
        for (final hs.DailyOutcome o in health)
          // Today's day totals and averages cover only part of it; the night
          // that ended today is whole.
          if (o.date.isBefore(unfinished) ||
              (metricCopy(o.metricId)?.night ?? false))
            DailyOutcome(date: o.date, metricId: o.metricId, value: o.value),
      ],
      from: range.start,
      through: addDays(range.end, -1),
    );
  }

  final List<HabitUse> uses;
  final List<DailyOutcome> outcomes;
  final DateTime from;
  final DateTime through;
}

class InsightsReport {
  const InsightsReport({required this.findings, required this.refused});

  /// Strongest first, by [HabitFinding.standardized]'s size.
  final List<HabitFinding> findings;

  /// One refusal for each habit with no finding of any kind on any outcome,
  /// the one that says most: entangled, then possibly chance, then logged
  /// unevenly, then within the noise, then a steady amount or time or a time
  /// that follows the amount, then too few days; on a tie, the days-with-and-without comparison's, then the one
  /// from the most days.
  final List<HabitRefusal> refused;
}

/// The next day's outcome after each day: the night that follows it for the
/// sleep and night metrics, the next day's value for the rest.
const int insightsLagDays = 1;

typedef _Comparison =
    List<HabitInsight> Function({
      required DailyHabitSeries habits,
      required OutcomeSeries outcomes,
      required String metricId,
      int lagDays,
      DateTime? from,
      DateTime? through,
      InsightGates gates,
    });

const List<_Comparison> _comparisons = <_Comparison>[
  whatFollows,
  doseFollows,
  lastUseFollows,
];

InsightsReport computeInsights(InsightsInput input) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  final List<HabitFinding> findings = <HabitFinding>[];
  final Map<String, List<HabitRefusal>> refusals =
      <String, List<HabitRefusal>>{};
  // The family for false-discovery control is the whole page: every habit
  // against every outcome, by use, amount and time, not one at a time.
  for (final HabitInsight insight in controlFalseDiscoveries(<HabitInsight>[
    for (final String metricId in outcomes.metricIds)
      if (metricCopy(metricId) != null)
        for (final _Comparison comparison in _comparisons)
          ...comparison(
            habits: habits,
            outcomes: outcomes,
            metricId: metricId,
            lagDays: insightsLagDays,
            from: input.from,
            through: input.through,
          ),
  ])) {
    switch (insight) {
      case HabitFinding():
        findings.add(insight);
      case HabitRefusal():
        refusals.putIfAbsent(insight.habitId, () => []).add(insight);
    }
  }
  findings.sort((a, b) {
    final int bySize = b.standardized.abs().compareTo(a.standardized.abs());
    return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
  });
  final Set<String> found = <String>{for (final f in findings) f.habitId};
  final List<String> refusedIds =
      refusals.keys.where((id) => !found.contains(id)).toList()..sort();
  return InsightsReport(
    findings: findings,
    refused: <HabitRefusal>[
      for (final String id in refusedIds) _mostTelling(refusals[id]!),
    ],
  );
}

HabitRefusal _mostTelling(List<HabitRefusal> refusals) {
  int rank(RefusalReason reason) => switch (reason) {
    RefusalReason.entangled => 0,
    RefusalReason.chance => 1,
    RefusalReason.uneven => 2,
    RefusalReason.withinNoise => 3,
    RefusalReason.steadyAmount ||
    RefusalReason.steadyTiming ||
    RefusalReason.followsAmount => 4,
    RefusalReason.tooFewDays => 5,
  };
  return refusals.reduce((a, b) {
    final int byReason = rank(a.reason).compareTo(rank(b.reason));
    if (byReason != 0) return byReason < 0 ? a : b;
    final int byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind < 0 ? a : b;
    return b.usableDays > a.usableDays ? b : a;
  });
}

enum DirectionWords { moreLess, higherLower }

/// How one outcome is named and measured on a card.
class MetricCopy {
  const MetricCopy(
    this.name, {
    required this.night,
    this.unit = '',
    this.decimals = 0,
    this.scale = 1,
    DirectionWords words = DirectionWords.higherLower,
  }) : _words = words;

  final String name;

  /// Read for the night after a day rather than the next day.
  final bool night;
  final String unit;
  final int decimals;

  /// From the stored value to the shown one (a 0 to 1 fraction to points).
  final double scale;
  final DirectionWords _words;

  String direction(double effect) => switch (_words) {
    DirectionWords.moreLess => effect < 0 ? 'less' : 'more',
    DirectionWords.higherLower => effect < 0 ? 'lower' : 'higher',
  };
}

MetricCopy? metricCopy(String metricId) => switch (metricId) {
  'sleepInBed' => _minutes('time in bed'),
  'sleepAsleep' => _minutes('time asleep'),
  'sleepAwake' => _minutes('time awake in the night'),
  'sleepCore' => _minutes('core sleep'),
  'sleepDeep' => _minutes('deep sleep'),
  'sleepREM' => _minutes('REM sleep'),
  'heartRateVariabilitySDNN' => const MetricCopy(
    'heart rate variability',
    night: false,
    unit: 'ms',
  ),
  'restingHeartRate' => const MetricCopy(
    'resting heart rate',
    night: false,
    unit: 'bpm',
    decimals: 1,
  ),
  'respiratoryRate' => const MetricCopy(
    'breathing rate',
    night: true,
    unit: 'breaths a minute',
    decimals: 1,
  ),
  'oxygenSaturation' => const MetricCopy(
    'blood oxygen',
    night: false,
    unit: 'percentage points',
    decimals: 1,
    scale: 100,
  ),
  'appleSleepingWristTemperature' => const MetricCopy(
    'wrist temperature',
    night: true,
    unit: '°C',
    decimals: 2,
  ),
  'stepCount' => const MetricCopy('step count', night: false),
  'activeEnergyBurned' => const MetricCopy(
    'active energy',
    night: false,
    unit: 'kcal',
    words: DirectionWords.moreLess,
  ),
  _ => null,
};

MetricCopy _minutes(String name) =>
    MetricCopy(name, night: true, unit: 'min', words: DirectionWords.moreLess);

String _amount(double value, MetricCopy copy, int decimals, String locale) {
  final String number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: decimals,
  ).format(value.abs() * copy.scale);
  return copy.unit.isEmpty ? number : '$number ${copy.unit}';
}

// Enough digits that neither end of the range rounds to zero, since a finding's
// range never includes it.
int _digits(HabitFinding finding, MetricCopy copy) {
  int digits = copy.decimals;
  final double nearest =
      [
        finding.interval.low.abs(),
        finding.interval.high.abs(),
      ].reduce((a, b) => a < b ? a : b) *
      copy.scale;
  while (digits < 3 && nearest < 0.5 * pow(10, -digits)) {
    digits++;
  }
  return digits;
}

/// "On nights after Coffee, your deep sleep averages 18 min less."; for an
/// amount, "Each extra drink of Coffee goes with your deep sleep that night
/// averaging 6 min less."; for a time, "A last Coffee an hour later goes
/// with ...". [unit] is the habit's, for an amount.
String findingSentence(
  HabitFinding finding,
  String habit,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final String amount = _amount(
    finding.effect,
    copy,
    _digits(finding, copy),
    locale,
  );
  final String direction = copy.direction(finding.effect);
  final String then = copy.night ? 'that night' : 'the next day';
  return switch (finding.kind) {
    InsightKind.use =>
      'On ${copy.night ? 'nights' : 'days'} after $habit, your ${copy.name} '
          'averages $amount $direction.',
    InsightKind.dose =>
      'Each extra ${_stepWords(finding.step, unit, locale)} of $habit goes '
          'with your ${copy.name} $then averaging $amount $direction.',
    InsightKind.lastUse =>
      'A last $habit an hour later goes with your ${copy.name} $then '
          'averaging $amount $direction.',
  };
}

// "drink", "10 minutes"; a count of times reads as uses.
String _stepWords(double step, Unit unit, String locale) {
  final String one = unit == Unit.time ? 'use' : unit.singular;
  final String other = unit == Unit.time ? 'uses' : unit.plural;
  if (step == 1) return one;
  final String number = NumberFormat.decimalPattern(locale).format(step);
  return '$number ${pluralWord(step, one: one, other: other)}';
}

/// "Range: 7 to 29 min less"; both ends share a sign, so one word serves.
String findingRange(HabitFinding finding, String locale) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final int digits = _digits(finding, copy);
  final double near = finding.effect < 0
      ? finding.interval.high
      : finding.interval.low;
  final double far = finding.effect < 0
      ? finding.interval.low
      : finding.interval.high;
  final String nearText = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(near.abs() * copy.scale);
  return 'Range: $nearText to ${_amount(far, copy, digits, locale)} '
      '${copy.direction(finding.effect)}';
}

/// "From 64 days, 22 of them with Coffee"; "From 64 days with Coffee" for an
/// amount or a time, which compare days of use alone.
String findingBasis(HabitFinding finding, String habit) {
  if (finding.kind != InsightKind.use) {
    return 'From ${finding.usableDays} days with $habit';
  }
  final int? used = finding.raw?.exposedDays;
  return used == null
      ? 'From ${finding.usableDays} days'
      : 'From ${finding.usableDays} days, $used of them with $habit';
}

/// Why a habit has no finding, in plain words; for an amount or a time, said
/// to be about that.
String refusalReason(
  HabitRefusal refusal,
  String Function(String habitId) nameOf, {
  InsightGates gates = const InsightGates(),
}) => switch (refusal.kind) {
  InsightKind.use => _useRefusal(refusal, nameOf, gates),
  InsightKind.dose => 'Amount: ${_amongUseRefusal(refusal, nameOf, gates)}',
  InsightKind.lastUse =>
    'Time of last use: ${_amongUseRefusal(refusal, nameOf, gates)}',
};

String _amongUseRefusal(
  HabitRefusal refusal,
  String Function(String habitId) nameOf,
  InsightGates gates,
) => switch (refusal.reason) {
  RefusalReason.tooFewDays =>
    'too few days with it yet: ${refusal.usableDays} of ${gates.minDays}',
  RefusalReason.steadyAmount =>
    'nearly the same each day, so there’s no difference to compare',
  RefusalReason.steadyTiming =>
    'nearly the same each day, so there’s no difference to compare',
  RefusalReason.followsAmount =>
    'later on days with more, so it can’t be told apart from the amount',
  RefusalReason.uneven =>
    'changed with the months, so it can’t be told apart from other changes',
  RefusalReason.entangled => switch (refusal.entangledWith) {
    final String other =>
      'moves with the days of ${nameOf(other)}, so the two can’t be told '
          'apart',
    null => 'moves with other habits’ days, so they can’t be told apart',
  },
  RefusalReason.withinNoise => 'within the noise, no clear difference',
  RefusalReason.chance => 'could be chance, one of many comparisons',
};

String _useRefusal(
  HabitRefusal refusal,
  String Function(String habitId) nameOf,
  InsightGates gates,
) => switch (refusal.reason) {
  RefusalReason.tooFewDays when refusal.usableDays < gates.minDays =>
    'Too few days yet: ${refusal.usableDays} of ${gates.minDays}',
  // The span ends on a use, so more days add days with it, not without.
  RefusalReason.tooFewDays
      when refusal.usableDays - refusal.exposedDays < gates.minUnexposedDays =>
    'Used almost every day: too few days without it to compare',
  RefusalReason.tooFewDays =>
    'Too few days with it yet: ${refusal.exposedDays} of '
        '${gates.minExposedDays}',
  RefusalReason.uneven =>
    'Used far more at some times than others, so it can’t be told apart from other changes',
  RefusalReason.entangled => switch (refusal.entangledWith) {
    final String other =>
      'Used together with ${nameOf(other)}, so the two can’t be told apart',
    null => 'Used together with other habits, so they can’t be told apart',
  },
  RefusalReason.withinNoise => 'Within the noise: no clear difference',
  RefusalReason.chance => 'Could be chance: one of many comparisons',
  // Set only on an amount or a time.
  RefusalReason.steadyAmount || RefusalReason.steadyTiming =>
    'Nearly the same each day, so there’s no difference to compare',
  RefusalReason.followsAmount =>
    'Later on days with more, so it can’t be told apart from the amount',
};
