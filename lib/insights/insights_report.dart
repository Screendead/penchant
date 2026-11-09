import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/what_follows.dart';

/// The days Insights reads: the 365 ending with [today].
({DateTime start, DateTime end}) insightsRange(DateTime today) {
  final DateTime end = addDays(startOfDay(today), 1);
  return (start: addDays(end, -365), end: end);
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

  /// Strongest first, by the size of the effect against the outcome's spread.
  final List<HabitFinding> findings;

  /// One refusal for each habit with no finding on any outcome, the one that
  /// says most: entangled, then within the noise, then too few days.
  final List<HabitRefusal> refused;
}

/// The next day's outcome after each day: the night that follows it for the
/// sleep and night metrics, the next day's value for the rest.
const int insightsLagDays = 1;

InsightsReport computeInsights(InsightsInput input) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  final List<HabitFinding> findings = <HabitFinding>[];
  final Map<String, List<HabitRefusal>> refusals =
      <String, List<HabitRefusal>>{};
  for (final String metricId in outcomes.metricIds) {
    if (metricCopy(metricId) == null) continue;
    for (final HabitInsight insight in whatFollows(
      habits: habits,
      outcomes: outcomes,
      metricId: metricId,
      lagDays: insightsLagDays,
      from: input.from,
      through: input.through,
    )) {
      switch (insight) {
        case HabitFinding():
          findings.add(insight);
        case HabitRefusal():
          refusals.putIfAbsent(insight.habitId, () => []).add(insight);
      }
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
    RefusalReason.withinNoise => 1,
    RefusalReason.tooFewDays => 2,
  };
  return refusals.reduce((a, b) {
    final int byReason = rank(a.reason).compareTo(rank(b.reason));
    if (byReason != 0) return byReason < 0 ? a : b;
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

/// "On nights after Coffee, your deep sleep averages 18 min less."
String findingSentence(HabitFinding finding, String habit, String locale) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final String when = copy.night ? 'nights' : 'days';
  final String amount = _amount(
    finding.effect,
    copy,
    _digits(finding, copy),
    locale,
  );
  return 'On $when after $habit, your ${copy.name} averages $amount '
      '${copy.direction(finding.effect)}.';
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

/// "From 64 days, 22 of them with Coffee"
String findingBasis(HabitFinding finding, String habit) {
  final int? used = finding.raw?.exposedDays;
  return used == null
      ? 'From ${finding.usableDays} days'
      : 'From ${finding.usableDays} days, $used of them with $habit';
}

/// Why a habit has no finding, in plain words.
String refusalReason(
  HabitRefusal refusal,
  String Function(String habitId) nameOf, {
  InsightGates gates = const InsightGates(),
}) => switch (refusal.reason) {
  RefusalReason.tooFewDays when refusal.usableDays < gates.minDays =>
    'Too few days yet: ${refusal.usableDays} of ${gates.minDays}',
  RefusalReason.tooFewDays => 'Too few days with and without it yet',
  RefusalReason.entangled => switch (refusal.entangledWith) {
    final String other =>
      'Used together with ${nameOf(other)}, so the two can’t be told apart',
    null => 'Used together with other habits, so they can’t be told apart',
  },
  RefusalReason.withinNoise => 'Within the noise: no clear difference',
};
