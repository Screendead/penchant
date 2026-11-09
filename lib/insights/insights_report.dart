import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/hours_after.dart';
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
    this.samples = const <String, List<hs.HealthSample>>{},
    this.archived = const <String>{},
  });

  factory InsightsInput.from({
    required Iterable<ViceActivity> activities,
    required Iterable<hs.DailyOutcome> health,
    required DateTime today,
    Map<String, List<hs.HealthSample>> samples =
        const <String, List<hs.HealthSample>>{},
    Set<String> archived = const <String>{},
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
      samples: samples,
      archived: archived,
    );
  }

  final List<HabitUse> uses;
  final List<DailyOutcome> outcomes;
  final DateTime from;
  final DateTime through;

  /// What [insightsHoursAfterPlan] asked for, by [hs.HealthSampleMetric.id],
  /// each sorted by start.
  final Map<String, List<hs.HealthSample>> samples;

  /// Habits the report says nothing about. Their uses stay in [uses], so they
  /// are still held constant when judging the others.
  final Set<String> archived;
}

/// The moments around uses whose samples Insights reads, with every window
/// ended by the start of [today], given [bed] ([hs.HealthSampleMetric.bed]).
HoursAfterPlan insightsHoursAfterPlan(
  List<HabitUse> uses,
  DateTime today, {
  List<hs.HealthSample> bed = const <hs.HealthSample>[],
}) => planHoursAfter(uses, startOfDay(today), bed: bed);

/// Where [insightsHoursAfterPlan] reads [hs.HealthSampleMetric.bed] from: the
/// evening before the first day a use can be judged.
DateTime insightsBedFrom(DateTime today) =>
    addDays(startOfDay(today), -hoursAfterLookbackDays - 1);

/// The sample measures read for [insightsHoursAfterPlan]'s spans: the judged
/// ones and steps.
const List<hs.HealthSampleMetric> insightsSampleMetrics =
    <hs.HealthSampleMetric>[
      ...hoursAfterMetrics,
      hs.HealthSampleMetric.stepCount,
    ];

class InsightsReport {
  const InsightsReport({
    required this.findings,
    required this.refused,
    this.hoursAfterChecks = 0,
  });

  /// How many hours-after comparisons ran: none without heart rate readings.
  final int hoursAfterChecks;

  /// Strongest first, by [HabitFinding.standardized]'s size; only those at or
  /// over their outcome's [metricFloor].
  final List<HabitFinding> findings;

  /// One refusal for each habit with no finding of any kind on any outcome,
  /// the one that says most: too small to matter, then entangled, then possibly chance, then logged
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
  final List<HabitInsight> hours = input.samples.isEmpty
      ? const <HabitInsight>[]
      : hoursAfter(
          plan: insightsHoursAfterPlan(
            input.uses,
            input.through,
            bed:
                input.samples[hs.HealthSampleMetric.bed.id] ??
                const <hs.HealthSample>[],
          ),
          uses: input.uses,
          samples: input.samples,
        );
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  final List<HabitFinding> findings = <HabitFinding>[];
  final Map<String, List<HabitRefusal>> refusals =
      <String, List<HabitRefusal>>{};
  // The family for false-discovery control is the whole page: every habit it
  // shows against every outcome, by use, amount and time, not one at a time.
  // An archived habit's comparisons are never shown, so they are not counted.
  for (final HabitInsight insight in controlFalseDiscoveries(<HabitInsight>[
    for (final String metricId in outcomes.metricIds)
      if (metricCopy(metricId) != null)
        for (final _Comparison comparison in _comparisons)
          for (final HabitInsight result in comparison(
            habits: habits,
            outcomes: outcomes,
            metricId: metricId,
            lagDays: insightsLagDays,
            from: input.from,
            through: input.through,
          ))
            if (!input.archived.contains(result.habitId)) result,
    for (final HabitInsight result in hours)
      if (!input.archived.contains(result.habitId)) result,
  ])) {
    switch (insight) {
      case HabitFinding() when practicalSize(insight) < 1:
        refusals.putIfAbsent(insight.habitId, () => []).add(_tooSmall(insight));
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
    hoursAfterChecks: hours.length,
    findings: findings,
    refused: <HabitRefusal>[
      for (final String id in refusedIds) _mostTelling(refusals[id]!),
    ],
  );
}

// Run after the many-comparisons correction, so it never changes which
// findings count as discoveries; it only hides those too small to matter.
HabitRefusal _tooSmall(HabitFinding f) => HabitRefusal(
  habitId: f.habitId,
  metricId: f.metricId,
  lagDays: f.lagDays,
  usableDays: f.usableDays,
  exposedDays: f.exposedDays,
  raw: f.raw,
  kind: f.kind,
  step: f.step,
  window: f.window,
  reason: RefusalReason.tooSmall,
  effect: f.effect,
  interval: f.interval,
  pValue: f.pValue,
);

/// The family a card groups its outcomes under.
enum MetricFamily {
  sleep('sleep'),
  heart('heart'),
  breathing('breathing'),
  temperature('temperature'),
  activity('activity');

  const MetricFamily(this.label);

  final String label;
}

/// The smallest difference in each outcome worth a card, in its stored units,
/// and its family. Claude's defaults (2026-11-09), pending Jack's review.
const Map<String, ({double floor, MetricFamily family})> metricFloors =
    <String, ({double floor, MetricFamily family})>{
      // A sixth of an hour: the least change in a night's sleep anyone would
      // plan around. The same for every stage and for time in bed or awake.
      'sleepInBed': (floor: 10, family: MetricFamily.sleep),
      'sleepAsleep': (floor: 10, family: MetricFamily.sleep),
      'sleepAwake': (floor: 10, family: MetricFamily.sleep),
      'sleepCore': (floor: 10, family: MetricFamily.sleep),
      'sleepDeep': (floor: 10, family: MetricFamily.sleep),
      'sleepREM': (floor: 10, family: MetricFamily.sleep),
      // About a tenth of a typical Watch SDNN of 30 to 60 ms.
      'heartRateVariabilitySDNN': (floor: 3, family: MetricFamily.heart),
      // Health shows resting and sleeping heart rate in whole bpm.
      'restingHeartRate': (floor: 1, family: MetricFamily.heart),
      'sleepingHeartRate': (floor: 1, family: MetricFamily.heart),
      // The hours-after sample measure: a minute's heart rate moves a few bpm
      // with posture alone, so twice the resting floor.
      'heartRate': (floor: 2, family: MetricFamily.heart),
      // About 2% of the 12 to 20 breaths a minute of an adult asleep.
      'respiratoryRate': (floor: 0.3, family: MetricFamily.breathing),
      // Stored 0 to 1; a Watch reads blood oxygen in whole percentage points.
      'oxygenSaturation': (floor: 0.01, family: MetricFamily.breathing),
      // A tenth of a degree, against nightly deviations that run to tenths.
      'appleSleepingWristTemperature': (
        floor: 0.1,
        family: MetricFamily.temperature,
      ),
      // About ten minutes' walk.
      'stepCount': (floor: 1000, family: MetricFamily.activity),
      // About ten minutes' brisk walk.
      'activeEnergyBurned': (floor: 50, family: MetricFamily.activity),
    };

/// [metricId]'s floor; infinite for an outcome with none, so nothing shows.
double metricFloor(String metricId) =>
    metricFloors[metricId]?.floor ?? double.infinity;

/// The difference [finding] stands for: an amount's or a time's effect across
/// the habit's interquartile range of days, a use's as it is.
double typicalEffect(HabitFinding finding) => switch (finding.spread) {
  final double spread => finding.effect / finding.step * spread,
  null => finding.effect,
};

/// [typicalEffect]'s size in [metricFloor]s: under 1 is too small to show.
double practicalSize(HabitFinding finding) =>
    typicalEffect(finding).abs() / metricFloor(finding.metricId);

/// One habit's findings in one [MetricFamily]: the largest by
/// [practicalSize] leads, the rest follow in the same order.
class InsightCard {
  const InsightCard({
    required this.family,
    required this.headline,
    this.others = const <HabitFinding>[],
  });

  final MetricFamily family;
  final HabitFinding headline;
  final List<HabitFinding> others;

  String get habitId => headline.habitId;
}

/// [findings] as one card per habit and family, largest headline first.
List<InsightCard> insightCards(List<HabitFinding> findings) {
  final Map<(String, MetricFamily), List<HabitFinding>> groups =
      <(String, MetricFamily), List<HabitFinding>>{};
  for (final HabitFinding f in findings) {
    final MetricFamily? family = metricFloors[f.metricId]?.family;
    if (family == null) continue;
    groups.putIfAbsent((f.habitId, family), () => []).add(f);
  }
  final List<InsightCard> cards = <InsightCard>[
    for (final MapEntry<(String, MetricFamily), List<HabitFinding>> group
        in groups.entries)
      () {
        final List<HabitFinding> sorted = group.value.toList()
          ..sort((a, b) => practicalSize(b).compareTo(practicalSize(a)));
        return InsightCard(
          family: group.key.$2,
          headline: sorted.first,
          others: sorted.sublist(1),
        );
      }(),
  ];
  return cards..sort((a, b) {
    final int bySize = practicalSize(
      b.headline,
    ).compareTo(practicalSize(a.headline));
    if (bySize != 0) return bySize;
    final int byHabit = a.habitId.compareTo(b.habitId);
    return byHabit != 0 ? byHabit : a.family.index.compareTo(b.family.index);
  });
}

HabitRefusal _mostTelling(List<HabitRefusal> refusals) {
  int rank(RefusalReason reason) => switch (reason) {
    RefusalReason.tooSmall => -1,
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
  'sleepingHeartRate' => const MetricCopy(
    'heart rate while asleep',
    night: true,
    unit: 'bpm',
    decimals: 1,
  ),
  // A sample measure, for InsightKind.hoursAfter alone.
  'heartRate' => const MetricCopy('heart rate', night: false, unit: 'bpm'),
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
    InsightKind.hoursAfter =>
      '${_windowWords(finding.window!)} $habit, your ${copy.name}, set '
          'against the hour before, averages $amount $direction than at the '
          'same time after waking without it.',
  };
}

/// A card's line under its headline: "More per extra drink: REM sleep 4 min
/// less", "Later last use: time asleep 11 min less per hour".
String findingLine(
  HabitFinding finding,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final String change =
      '${copy.name} ${_amount(finding.effect, copy, _digits(finding, copy), locale)} '
      '${copy.direction(finding.effect)}';
  return switch (finding.kind) {
    InsightKind.use => 'On ${copy.night ? 'nights' : 'days'} after it: $change',
    InsightKind.dose =>
      'More per extra ${_stepWords(finding.step, unit, locale)}: $change',
    InsightKind.lastUse => 'Later last use: $change per hour',
    InsightKind.hoursAfter => '${_windowWords(finding.window!)} it: $change',
  };
}

String _windowWords(HourWindow w) => switch ((w.start, w.end)) {
  (0, 30) => 'In the half hour after',
  (30, 60) => 'Half an hour to an hour after',
  (60, 120) => 'One to two hours after',
  (120, 240) => 'Two to four hours after',
  _ => '${w.start} to ${w.end} minutes after',
};

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
  if (finding.kind == InsightKind.hoursAfter) {
    return 'From ${finding.exposedDays} days with $habit, against '
        '${finding.usableDays - finding.exposedDays} days at the same time '
        'after waking with none of it within 4 hours';
  }
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
  InsightKind.hoursAfter => 'Hours after it: ${_hoursAfterRefusal(refusal)}',
};

String _hoursAfterRefusal(HabitRefusal refusal) {
  const HoursAfterGates gates = HoursAfterGates();
  final String name = metricCopy(refusal.metricId)?.name ?? 'Health';
  final String days = '${refusal.exposedDays} days of ${gates.minEventDays}';
  return switch (refusal.reason) {
    RefusalReason.tooFewDays => switch (refusal.shortfall) {
      HoursAfterShortfall.uses ||
      null => 'too few uses with none of it in the 4 hours before yet: $days',
      HoursAfterShortfall.noSleep =>
        'needs your sleep in Health, to time each use from waking: most uses '
            'have no night recorded before them',
      HoursAfterShortfall.nearSleep =>
        'most uses come within an hour of waking or within 4 hours of bed, '
            'when $name moves anyway',
      HoursAfterShortfall.otherHabit =>
        'another habit is logged within 4 hours of most of its uses',
      HoursAfterShortfall.sameHabit =>
        'used again within a few hours most times, so the hours after one '
            'use run into the next',
      HoursAfterShortfall.readings =>
        'Health holds too few $name readings around its uses, '
            '${gates.minSamples} before and after each',
      HoursAfterShortfall.walk => 'most of its uses come with a walk',
      HoursAfterShortfall.controls =>
        'too few nearby days clear of it at the same time after waking to '
            'compare with',
    },
    RefusalReason.chance => 'could be chance, one of many comparisons',
    RefusalReason.tooSmall => 'too small to matter: ${_underFloor(refusal)}',
    _ => 'within the noise, no clear difference',
  };
}

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
  RefusalReason.tooSmall =>
    'too small to matter: ${_underFloor(refusal)} across your usual range',
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
  RefusalReason.tooSmall => 'Too small to matter: ${_underFloor(refusal)}',
  // Set only on an amount or a time.
  RefusalReason.steadyAmount || RefusalReason.steadyTiming =>
    'Nearly the same each day, so there’s no difference to compare',
  RefusalReason.followsAmount =>
    'Later on days with more, so it can’t be told apart from the amount',
};

// "under 10 min a night of REM sleep", "under 1,000 a day of step count".
String _underFloor(HabitRefusal refusal) {
  final MetricCopy copy = metricCopy(refusal.metricId)!;
  final String floor = NumberFormat.decimalPattern(
    'en',
  ).format(metricFloor(refusal.metricId) * copy.scale);
  final String unit = copy.unit.isEmpty ? '' : ' ${copy.unit}';
  final String per = switch (metricFloors[refusal.metricId]?.family) {
    MetricFamily.sleep => ' a night',
    MetricFamily.activity => ' a day',
    _ => '',
  };
  return 'under $floor$unit$per of ${copy.name}';
}
