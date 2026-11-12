import 'dart:math';

import 'package:intl/intl.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/cycle_phase.dart';
import 'package:tracker/insights/daylight.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/from_journal.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/health_source.dart' as hs;
import 'package:tracker/insights/hours_after.dart';
import 'package:tracker/insights/measure_shifts.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/places.dart';
import 'package:tracker/insights/recovery.dart';
import 'package:tracker/insights/replacement.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/trigger_amounts.dart';
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
    this.events = const <CalendarEvent>[],
    this.stays = const <PlaceStay>[],
    this.conditions = const <DayCondition>[],
  });

  factory InsightsInput.from({
    required Iterable<ViceActivity> activities,
    required Iterable<hs.DailyOutcome> health,
    required DateTime today,
    Map<String, List<hs.HealthSample>> samples =
        const <String, List<hs.HealthSample>>{},
    Set<String> archived = const <String>{},
    List<CalendarEvent> events = const <CalendarEvent>[],
    Iterable<hs.DailyOutcome> reminders = const <hs.DailyOutcome>[],
    List<PlaceStay> stays = const <PlaceStay>[],
    RoughLocation? location,
  }) {
    final ({DateTime start, DateTime end}) range = insightsRange(today);
    final DateTime unfinished = startOfDay(today);
    // A locked entry counts: its vice and quantity are plaintext.
    final List<HabitUse> uses = habitUsesFrom(activities).toList();
    DateTime? firstUse;
    for (final HabitUse u in uses) {
      if (firstUse == null || u.at.isBefore(firstUse)) firstUse = u.at;
    }
    return InsightsInput(
      uses: uses,
      outcomes: withEnoughMood(
        withSessionZeros(<DailyOutcome>[
          for (final hs.DailyOutcome o in <hs.DailyOutcome>[
            ...health,
            ...reminders,
          ])
            // Today's day totals and averages cover only part of it; the night
            // that ended today is whole.
            if (o.metricId != hs.HealthMetric.menstrualFlow.id &&
                (o.date.isBefore(unfinished) ||
                    (metricCopy(o.metricId)?.night ?? false) ||
                    o.metricId == sleepOnsetId))
              DailyOutcome(date: o.date, metricId: o.metricId, value: o.value),
        ], through: addDays(unfinished, -1)),
      ),
      from: range.start,
      through: addDays(range.end, -1),
      samples: samples,
      archived: archived,
      events: events,
      stays: stays,
      conditions: <DayCondition>[
        cyclePhases(<DateTime>[
          for (final hs.DailyOutcome o in health)
            if (o.metricId == hs.HealthMetric.menstrualFlow.id && o.value > 0)
              o.date,
        ]),
        if (location != null && firstUse != null)
          dayLengths(location, from: firstUse, through: range.end),
      ],
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

  /// The calendar's timed events over the journal's span; empty without
  /// calendar access.
  final List<CalendarEvent> events;

  /// Time spent at the person's own places; empty without location access.
  final List<PlaceStay> stays;

  /// What the day-after comparisons hold fixed where there are enough days:
  /// the cycle's phase ([cyclePhases]) and the day's length ([dayLengths]),
  /// never outcomes of their own.
  final List<DayCondition> conditions;
}

/// The fewest days with a session a [hs.sessionMetricIds] outcome needs to be
/// judged at all: under it, a series of nearly all zeros would only add
/// comparisons to the false-discovery family that cannot find anything.
const int minSessionDays = 14;

/// [outcomes] with each [hs.sessionMetricIds] metric's days without a session
/// as 0, from its first day with one through [through]. Without the metric
/// when it has fewer than [minSessionDays] days with a session, or when its
/// floor ([metricFloors]) cannot be reached: no day's total reaches it. Every
/// day lies between 0 and that largest day, so no two sets of days can differ
/// by the floor in either direction, and its comparisons would only enlarge
/// the false-discovery family. The rule reads the metric's own days alone,
/// never which days followed a habit, so it cannot favour a finding. It is
/// exact for the with-and-without comparisons and conservative (it keeps
/// some unreachable metrics) since the person's floor is never under the
/// literature's; an amount or time slope across a habit's range is taken to
/// stay inside the days' range too. A person with none has no rows, which
/// stays no data: Health answers a refused read with nothing, the same as an
/// empty one.
List<DailyOutcome> withSessionZeros(
  List<DailyOutcome> outcomes, {
  required DateTime through,
}) {
  final Map<String, Set<DateTime>> sessionDays = <String, Set<DateTime>>{};
  final Map<String, double> largest = <String, double>{};
  for (final DailyOutcome o in outcomes) {
    if (hs.sessionMetricIds.contains(o.metricId) && o.value > 0) {
      (sessionDays[o.metricId] ??= <DateTime>{}).add(o.date);
      largest[o.metricId] = max(largest[o.metricId] ?? 0, o.value);
    }
  }
  final Set<String> judged = <String>{
    for (final MapEntry<String, Set<DateTime>> metric in sessionDays.entries)
      if (metric.value.length >= minSessionDays &&
          largest[metric.key]! >= (metricFloors[metric.key]?.floor ?? 0))
        metric.key,
  };
  final List<DailyOutcome> filled = <DailyOutcome>[
    for (final DailyOutcome o in outcomes)
      if (!hs.sessionMetricIds.contains(o.metricId) ||
          judged.contains(o.metricId))
        o,
  ];
  for (final MapEntry<String, Set<DateTime>> metric in sessionDays.entries) {
    if (!judged.contains(metric.key)) continue;
    final Set<DateTime> known = <DateTime>{
      for (final DailyOutcome o in outcomes)
        if (o.metricId == metric.key) o.date,
    };
    for (
      DateTime day = metric.value.reduce((a, b) => a.isBefore(b) ? a : b);
      !day.isAfter(through);
      day = addDays(day, 1)
    ) {
      if (!known.contains(day)) {
        filled.add(DailyOutcome(date: day, metricId: metric.key, value: 0));
      }
    }
  }
  return filled;
}

/// The fewest days with a mood log before [hs.HealthMetric.moodValence] is
/// judged at all (Jack, round 16 `mood-floor` A): most people log mood now and
/// then, and a handful of days would only add comparisons to the
/// false-discovery family.
const int minMoodDays = 14;

/// [outcomes] without [hs.HealthMetric.moodValence] when it has fewer than
/// [minMoodDays] days or every day's value is the same, so it has no spread
/// to set its floor ([FloorRule.ownSpread]) and nothing could differ. Reads
/// the person's days alone, never which followed a habit.
List<DailyOutcome> withEnoughMood(List<DailyOutcome> outcomes) {
  final String mood = hs.HealthMetric.moodValence.id;
  final List<double> days = <double>[
    for (final DailyOutcome o in outcomes)
      if (o.metricId == mood) o.value,
  ];
  if (days.isEmpty) return outcomes;
  final bool judged =
      days.length >= minMoodDays && days.any((v) => v != days.first);
  return judged
      ? outcomes
      : <DailyOutcome>[
          for (final DailyOutcome o in outcomes)
            if (o.metricId != mood) o,
        ];
}

/// The moments around uses whose samples Insights reads, with every window
/// ended by the start of [today], given [bed] ([hs.HealthSampleMetric.bed])
/// and, for days with no night in it, [wakingSteps] read over
/// [insightsWakingReads].
HoursAfterPlan insightsHoursAfterPlan(
  List<HabitUse> uses,
  DateTime today, {
  List<hs.HealthSample> bed = const <hs.HealthSample>[],
  List<hs.HealthSample> wakingSteps = const <hs.HealthSample>[],
}) =>
    planHoursAfter(uses, startOfDay(today), bed: bed, wakingSteps: wakingSteps);

/// The spans of steps [insightsHoursAfterPlan] guesses waking from: one per
/// day near a use that [bed] holds no night for.
List<({DateTime start, DateTime end})> insightsWakingReads(
  List<HabitUse> uses,
  DateTime today, {
  List<hs.HealthSample> bed = const <hs.HealthSample>[],
}) => hoursAfterWakingReads(uses, startOfDay(today), bed: bed);

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
    this.floors = const <String, double>{},
    this.follows = const <HabitFollows>[],
    this.beforeUse = const <BeforeUse>[],
    this.payoffs = const <Payoff>[],
    this.replacements = const <Replacement>[],
    this.shifts = const <MeasureShift>[],
    this.afterEvent = const <AfterEvent>[],
    this.atPlace = const <AtPlace>[],
    this.recovery = const <Recovery>[],
    this.triggers = const <HabitTriggers>[],
  });

  /// Each habit's tagged triggers against its other tagged entries, findings
  /// and refusals, judged in the same family as [findings].
  final List<HabitTriggers> triggers;

  /// Each habit's measures over the nights after its heavy days, findings
  /// and refusals, judged in the same family as [findings].
  final List<Recovery> recovery;

  /// The measures whose level changed and stayed changed, by date, judged in
  /// the same family as [findings]; only those found.
  final List<MeasureShift> shifts;

  /// Each measure since a habit fell and stayed lower, findings and
  /// refusals, judged in the same family as [findings].
  final List<Payoff> payoffs;

  /// Each other habit's amount since a habit fell, findings and refusals,
  /// judged in the same family as [findings].
  final List<Replacement> replacements;

  /// Whether each habit follows calendar events, findings and refusals,
  /// judged in the same family as [findings].
  final List<AfterEvent> afterEvent;

  /// Whether each habit is logged at each place more than the time spent
  /// there would give, findings and refusals, judged in the same family as
  /// [findings].
  final List<AtPlace> atPlace;

  /// Every pair of habits shown, one following the other within minutes,
  /// each with its verdict, judged in the same family as [findings].
  final List<HabitFollows> follows;

  /// What came before each habit's use, findings and refusals, judged in the
  /// same family as [findings].
  final List<BeforeUse> beforeUse;

  /// Each outcome's floor for this person, from [resolveFloors]; an outcome
  /// missing here falls back to [metricFloors]' own.
  final Map<String, double> floors;

  /// How many hours-after comparisons ran: none without heart rate readings.
  final int hoursAfterChecks;

  /// Strongest first, by [HabitFinding.standardized]'s size; only those at or
  /// over their outcome's floor in [floors].
  final List<HabitFinding> findings;

  /// One refusal for each habit with no finding of any kind on any outcome,
  /// the one that says most: too small to matter, then entangled, then
  /// possibly chance, then logged unevenly, then resting on one day, then
  /// within the noise, then a steady amount or time or a time that follows the
  /// amount, then too few days; on a tie, the days-with-and-without
  /// comparison's, then the one from the most days.
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
      List<DayCondition> conditions,
    });

const List<_Comparison> _comparisons = <_Comparison>[
  whatFollows,
  doseFollows,
  lastUseFollows,
  doseLineFollows,
  lastUseLineFollows,
];

InsightsReport computeInsights(InsightsInput input) {
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(input.uses);
  final HoursAfterPlan? plan = input.samples.isEmpty
      ? null
      : insightsHoursAfterPlan(
          input.uses,
          input.through,
          bed:
              input.samples[hs.HealthSampleMetric.bed.id] ??
              const <hs.HealthSample>[],
          wakingSteps:
              input.samples[wakingStepsKey] ?? const <hs.HealthSample>[],
        );
  final List<HabitInsight> hours = plan == null
      ? const <HabitInsight>[]
      : hoursAfter(plan: plan, uses: input.uses, samples: input.samples);
  final OutcomeSeries outcomes = OutcomeSeries.fromOutcomes(input.outcomes);
  final Map<String, double> floors = resolveFloors(outcomes);
  final List<HabitFinding> findings = <HabitFinding>[];
  final Map<String, List<HabitRefusal>> refusals =
      <String, List<HabitRefusal>>{};
  // The family for false-discovery control is the whole page: every habit it
  // shows against every outcome, by use, amount and time and a line in each,
  // what came before each use, each night after a heavy day and each tagged
  // trigger, not one at a time.
  // An archived habit's comparisons are never shown, so they are not counted.
  final List<HabitInsight> after = <HabitInsight>[
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
            conditions: input.conditions,
          ))
            if (!input.archived.contains(result.habitId)) result,
    for (final HabitInsight result in hours)
      if (!input.archived.contains(result.habitId)) result,
  ];
  // Today's use is not over, and may yet be followed, so the last whole day
  // is yesterday.
  final List<BeforeUse> before = <BeforeUse>[
    ...beforeUse(
      uses: input.uses,
      outcomes: outcomes,
      through: addDays(input.through, -1),
      skip: input.archived,
    ),
    if (plan != null)
      ...hourBefore(
        plan: plan,
        uses: input.uses,
        samples: input.samples,
        skip: input.archived,
      ),
  ];
  final List<Recovery> recovering = recoveryAfterHeavyDays(
    uses: input.uses,
    outcomes: outcomes,
    through: input.through,
    floors: floors,
    skip: input.archived,
  );
  final List<Payoff> payoffs = payoff(
    uses: input.uses,
    outcomes: outcomes,
    metricIds: <String>[
      for (final String metricId in outcomes.metricIds)
        if (metricCopy(metricId) != null && metricFloors.containsKey(metricId))
          metricId,
    ]..sort(),
    through: addDays(input.through, -1),
    skip: input.archived,
  );
  final List<Replacement> replacements = replacement(
    uses: input.uses,
    through: addDays(input.through, -1),
    skip: input.archived,
  );
  final List<AfterEvent> calendar = afterEvent(
    uses: input.uses,
    events: input.events,
    through: addDays(input.through, -1),
    skip: input.archived,
  );
  final List<AtPlace> places = atPlace(
    uses: input.uses,
    stays: input.stays,
    through: addDays(input.through, -1),
    skip: input.archived,
  );
  final List<HabitFollows> follows = habitFollows(
    uses: input.uses,
    through: addDays(input.through, -1),
    skip: input.archived,
    bed:
        input.samples[hs.HealthSampleMetric.bed.id] ??
        const <hs.HealthSample>[],
  );
  final List<HabitTriggers> triggered = triggerAmounts(
    uses: input.uses,
    through: addDays(input.through, -1),
    skip: input.archived,
  );
  final List<double> afterPs = <double>[
    for (final HabitInsight i in after) ?insightPValue(i),
  ];
  final List<double> triggerPs = triggerPValues(triggered);
  final List<double> beforePs = <double>[
    for (final BeforeUse b in before) ?b.pValue,
  ];
  final List<double> followsPs = <double>[
    for (final HabitFollows f in follows) ?f.pValue,
  ];
  final List<double> payoffPs = <double>[
    for (final Payoff p in payoffs) ?p.pValue,
  ];
  final List<double> calendarPs = <double>[
    for (final AfterEvent a in calendar) ?a.pValue,
  ];
  final List<double> placePs = <double>[
    for (final AtPlace a in places) ?a.pValue,
  ];
  final List<double> replacementPs = <double>[
    for (final Replacement r in replacements) ?r.pValue,
  ];
  final ({List<MeasureShift> shifts, List<double> searched}) shifted =
      measureShifts(
        outcomes: outcomes,
        habits: habits,
        through: input.through,
        skip: input.archived,
      );
  final List<double> shiftPs = <double>[
    for (final MeasureShift s in shifted.shifts) s.shift.pValue,
    ...shifted.searched,
  ];
  final List<double> recoveryPs = recoveryPValues(recovering);
  for (final HabitInsight insight in controlFalseDiscoveries(
    after,
    alongside: <double>[
      ...beforePs,
      ...triggerPs,
      ...followsPs,
      ...calendarPs,
      ...placePs,
      ...shiftPs,
      ...payoffPs,
      ...replacementPs,
      ...recoveryPs,
    ],
  )) {
    switch (insight) {
      case HabitFinding() when practicalSize(insight, floors: floors) < 1:
        refusals.putIfAbsent(insight.habitId, () => []).add(_tooSmall(insight));
      case HabitFinding():
        findings.add(insight);
      case HabitRefusal():
        refusals.putIfAbsent(insight.habitId, () => []).add(insight);
    }
  }
  final List<HabitFinding> shown = oneOfSlopeAndLine(findings)
    ..sort((a, b) {
      final int bySize = b.standardized.abs().compareTo(a.standardized.abs());
      return bySize != 0 ? bySize : a.habitId.compareTo(b.habitId);
    });
  final Set<String> found = <String>{for (final f in shown) f.habitId};
  final List<String> refusedIds =
      refusals.keys.where((id) => !found.contains(id)).toList()..sort();
  return InsightsReport(
    hoursAfterChecks: hours.length,
    floors: floors,
    follows: judgeHabitFollows(
      follows,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...triggerPs,
        ...calendarPs,
        ...placePs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
        ...recoveryPs,
      ],
    ),
    beforeUse: judgeBeforeUse(
      before,
      alongside: <double>[
        ...afterPs,
        ...triggerPs,
        ...followsPs,
        ...calendarPs,
        ...placePs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
        ...recoveryPs,
      ],
      sizeOf: (BeforeUse b) => practicalSize(b.asFinding, floors: floors),
    ),
    recovery: judgeRecovery(
      recovering,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...triggerPs,
        ...followsPs,
        ...calendarPs,
        ...placePs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
      ],
    ),
    payoffs: judgePayoffs(
      payoffs,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...triggerPs,
        ...followsPs,
        ...calendarPs,
        ...placePs,
        ...shiftPs,
        ...replacementPs,
        ...recoveryPs,
      ],
      sizeOf: (Payoff p) => practicalSize(p.asFinding, floors: floors),
    ),
    replacements: judgeReplacements(
      replacements,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...triggerPs,
        ...followsPs,
        ...calendarPs,
        ...placePs,
        ...shiftPs,
        ...payoffPs,
        ...recoveryPs,
      ],
    ),
    afterEvent: judgeAfterEvent(
      calendar,
      alongside: <double>[
        ...afterPs,
        ...placePs,
        ...beforePs,
        ...triggerPs,
        ...followsPs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
        ...recoveryPs,
      ],
    ),
    atPlace: judgeAtPlace(
      places,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...followsPs,
        ...calendarPs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
        ...recoveryPs,
      ],
    ),
    shifts:
        judgeMeasureShifts(
            shifted.shifts,
            alongside: <double>[
              ...shifted.searched,
              ...afterPs,
              ...beforePs,
              ...triggerPs,
              ...followsPs,
              ...calendarPs,
              ...placePs,
              ...payoffPs,
              ...replacementPs,
              ...recoveryPs,
            ],
            floors: floors,
            q: const InsightGates().falseDiscoveryRate,
          ).where((MeasureShift s) => s.found).toList()
          ..sort((a, b) => a.shift.at.compareTo(b.shift.at)),
    triggers: judgeTriggerAmounts(
      triggered,
      alongside: <double>[
        ...afterPs,
        ...beforePs,
        ...followsPs,
        ...calendarPs,
        ...shiftPs,
        ...payoffPs,
        ...replacementPs,
        ...recoveryPs,
      ],
    ),
    findings: shown,
    refused: <HabitRefusal>[
      for (final String id in refusedIds) _mostTelling(refusals[id]!),
    ],
  );
}

/// [findings] with one way of saying it per habit and outcome: where an
/// amount or a time of last use has both a slope ([InsightKind.dose],
/// [InsightKind.lastUse]) and a line ([InsightKind.doseLine],
/// [InsightKind.lastUseLine]), the line when its p-value, already multiplied
/// by the cuts tried, is still the smaller, else the slope. Run on findings
/// that passed the many-comparisons correction, so it only hides.
List<HabitFinding> oneOfSlopeAndLine(List<HabitFinding> findings) {
  const Map<InsightKind, InsightKind> slopeOf = <InsightKind, InsightKind>{
    InsightKind.doseLine: InsightKind.dose,
    InsightKind.lastUseLine: InsightKind.lastUse,
  };
  final Set<HabitFinding> hidden = Set<HabitFinding>.identity();
  for (final HabitFinding line in findings) {
    final InsightKind? kind = slopeOf[line.kind];
    if (kind == null) continue;
    for (final HabitFinding slope in findings) {
      if (slope.kind == kind &&
          slope.habitId == line.habitId &&
          slope.metricId == line.metricId) {
        hidden.add(line.pValue < slope.pValue ? slope : line);
      }
    }
  }
  return <HabitFinding>[
    for (final HabitFinding f in findings)
      if (!hidden.contains(f)) f,
  ];
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
  cut: f.cut,
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
  activity('activity'),
  mindfulness('mindfulness'),
  reminders('reminders'),
  mood('mood');

  const MetricFamily(this.label);

  final String label;
}

/// How an outcome's floor is worked out for one person.
enum FloorRule {
  /// The floor as it stands.
  fixed,

  /// [remShareOfNight] of the person's usual time asleep; the floor as it
  /// stands with under [minNoisePairs] nights of it.
  shareOfNight,

  /// [noiseShare] of the person's own night-to-night variation alone; the
  /// floor as it stands when there are too few nights to measure it.
  ownNoise,

  /// [noiseShare] of the standard deviation of the person's daily values,
  /// over every day with one (not only next-door days, which a measure logged
  /// now and then seldom has); the floor as it stands under [minNoisePairs]
  /// days.
  ownSpread,
}

/// The smallest difference in each outcome worth a card, in its stored units,
/// its family, and how it is resolved per person ([resolveFloors]). Each is
/// the smallest change a study has shown to go with a measurable effect;
/// sources, and the reasoning where none was usable, are in
/// docs/insights/floors-literature.md.
const Map<String, ({double floor, MetricFamily family, FloorRule rule})>
metricFloors = <String, ({double floor, MetricFamily family, FloorRule rule})>{
  // Kept: no source shows an effect of time in bed itself.
  'sleepInBed': (floor: 10, family: MetricFamily.sleep, rule: FloorRule.fixed),
  // Sourced: Al Khatib 2018.
  'sleepAsleep': (floor: 21, family: MetricFamily.sleep, rule: FloorRule.fixed),
  // Consensus: the AASM's clinical-significance threshold (Sateia 2017).
  'sleepAwake': (floor: 20, family: MetricFamily.sleep, rule: FloorRule.fixed),
  // Kept: no source isolates core or deep sleep at a small change.
  'sleepCore': (floor: 10, family: MetricFamily.sleep, rule: FloorRule.fixed),
  'sleepDeep': (floor: 10, family: MetricFamily.sleep, rule: FloorRule.fixed),
  // Sourced: Leary 2020, per 5 percentage points of the night in REM.
  'sleepREM': (
    floor: 10,
    family: MetricFamily.sleep,
    rule: FloorRule.shareOfNight,
  ),
  // Sourced: Javaloyes 2019, half a standard deviation of the person's own.
  'heartRateVariabilitySDNN': (
    floor: 3,
    family: MetricFamily.heart,
    rule: FloorRule.ownNoise,
  ),
  // Sourced: Vazir 2018 (ARIC), per 5 bpm; asleep, inferred from it.
  'restingHeartRate': (
    floor: 5,
    family: MetricFamily.heart,
    rule: FloorRule.fixed,
  ),
  'sleepingHeartRate': (
    floor: 5,
    family: MetricFamily.heart,
    rule: FloorRule.fixed,
  ),
  // Kept: the hours-after sample measure; a minute's heart rate moves a few
  // bpm with posture alone.
  'heartRate': (floor: 2, family: MetricFamily.heart, rule: FloorRule.fixed),
  // Kept: Baumert 2019 gives a cut-off, not a change.
  'respiratoryRate': (
    floor: 0.3,
    family: MetricFamily.breathing,
    rule: FloorRule.fixed,
  ),
  // Inferred: Zoccali 2002, per point, in people on dialysis. Stored 0 to 1.
  'oxygenSaturation': (
    floor: 0.01,
    family: MetricFamily.breathing,
    rule: FloorRule.fixed,
  ),
  // Kept: no source gives an effect of a change in wrist temperature.
  'appleSleepingWristTemperature': (
    floor: 0.1,
    family: MetricFamily.temperature,
    rule: FloorRule.fixed,
  ),
  // Sourced: Banach 2023, per 500 steps.
  'stepCount': (
    floor: 500,
    family: MetricFamily.activity,
    rule: FloorRule.fixed,
  ),
  // Inferred: Strain 2020's 5 kJ/kg/day at a 70 kg reference.
  'activeEnergyBurned': (
    floor: 85,
    family: MetricFamily.activity,
    rule: FloorRule.fixed,
  ),
  // Inferred: Wen 2011's 15 min of exercise a day, self-reported.
  'workoutMinutes': (
    floor: 15,
    family: MetricFamily.activity,
    rule: FloorRule.fixed,
  ),
  // Inferred: Basso 2019's 13 min of meditation a day for 8 weeks.
  'mindfulMinutes': (
    floor: 13,
    family: MetricFamily.mindfulness,
    rule: FloorRule.fixed,
  ),
  // Kept: no source sizes a change in reminders done or missed; one whole
  // reminder a day, raised to the person's own noise as every floor is.
  'remindersCompleted': (
    floor: 1,
    family: MetricFamily.reminders,
    rule: FloorRule.fixed,
  ),
  'remindersMissed': (
    floor: 1,
    family: MetricFamily.reminders,
    rule: FloorRule.fixed,
  ),
  // Jack's call (round 16 `mood-floor` A): half the person's own SD of daily
  // valence, after Norman 2003's half a standard deviation. The 2 here, the
  // scale's whole width, would show nothing; withEnoughMood leaves mood out
  // before it could apply.
  'moodValence': (
    floor: 2,
    family: MetricFamily.mood,
    rule: FloorRule.ownSpread,
  ),
};

/// Leary 2020's step: 5 percentage points of the night in REM.
const double remShareOfNight = 0.05;

/// The share of the person's night-to-night variation no floor goes under:
/// half, the smallest worthwhile change Javaloyes 2019 acts on, and half of
/// [FloorRule.ownSpread]'s standard deviation (Norman 2003).
const double noiseShare = 0.5;

/// The fewest pairs of next-door days [typicalError] needs.
const int minNoisePairs = 14;

/// [days]' night-to-night variation: the standard deviation of the change
/// from each day to the next, over days that both have a value, divided by
/// the square root of 2 (Hopkins 2000's typical error). Null under
/// [minNoisePairs] pairs.
double? typicalError(Map<DateTime, double> days) {
  final List<double> changes = <double>[
    for (final MapEntry<DateTime, double> day in days.entries)
      if (days[addDays(day.key, 1)] case final double next) next - day.value,
  ];
  if (changes.length < minNoisePairs) return null;
  return sqrt(sampleVariance(changes) / 2);
}

/// Each outcome's floor for the person behind [outcomes]: [metricFloors]'
/// rule, then raised to [noiseShare] of their night-to-night variation, so a
/// floor never sits inside it. Outcomes [outcomes] lacks keep their own, as
/// does one whose rule resolves to nothing (a flat series, nights of no sleep):
/// a floor of 0 would pass every finding with an infinite size.
Map<String, double> resolveFloors(OutcomeSeries outcomes) {
  final Map<DateTime, double> asleep = outcomes.days('sleepAsleep');
  return <String, double>{
    for (final MapEntry<
          String,
          ({double floor, MetricFamily family, FloorRule rule})
        >
        metric
        in metricFloors.entries)
      metric.key: () {
        final double? noise = switch (typicalError(outcomes.days(metric.key))) {
          final double error => noiseShare * error,
          null => null,
        };
        final double floor = switch (metric.value.rule) {
          FloorRule.fixed => metric.value.floor,
          // The median over every night with time asleep, REM or not.
          FloorRule.shareOfNight when asleep.length >= minNoisePairs =>
            remShareOfNight * median(asleep.values.toList()),
          FloorRule.shareOfNight => metric.value.floor,
          FloorRule.ownNoise => noise ?? metric.value.floor,
          FloorRule.ownSpread => switch (outcomes
              .days(metric.key)
              .values
              .toList()) {
            final List<double> days when days.length >= minNoisePairs =>
              noiseShare * sqrt(sampleVariance(days)),
            _ => metric.value.floor,
          },
        };
        final double resolved = noise == null ? floor : max(floor, noise);
        return resolved > 0 ? resolved : metric.value.floor;
      }(),
  };
}

/// [metricId]'s floor: [floors]' for this person, else [metricFloors]' own;
/// infinite for an outcome with none, so nothing shows.
double metricFloor(
  String metricId, [
  Map<String, double> floors = const <String, double>{},
]) => floors[metricId] ?? metricFloors[metricId]?.floor ?? double.infinity;

/// The difference [finding] stands for: an amount's or a time's effect across
/// the habit's interquartile range of days, a use's as it is.
double typicalEffect(HabitFinding finding) => switch (finding.spread) {
  final double spread => finding.effect / finding.step * spread,
  null => finding.effect,
};

/// [typicalEffect]'s size in [metricFloor]s: under 1 is too small to show.
double practicalSize(
  HabitFinding finding, {
  Map<String, double> floors = const <String, double>{},
}) => typicalEffect(finding).abs() / metricFloor(finding.metricId, floors);

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
List<InsightCard> insightCards(
  List<HabitFinding> findings, {
  Map<String, double> floors = const <String, double>{},
}) {
  double size(HabitFinding f) => practicalSize(f, floors: floors);
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
          ..sort((a, b) => size(b).compareTo(size(a)));
        return InsightCard(
          family: group.key.$2,
          headline: sorted.first,
          others: sorted.sublist(1),
        );
      }(),
  ];
  return cards..sort((a, b) {
    final int bySize = size(b.headline).compareTo(size(a.headline));
    if (bySize != 0) return bySize;
    final int byHabit = a.habitId.compareTo(b.habitId);
    return byHabit != 0 ? byHabit : a.family.index.compareTo(b.family.index);
  });
}

/// How much a refusal says, lowest first: too small to matter, then
/// entangled, then possibly chance, then logged unevenly, then resting on one
/// day, then within the noise, then a steady amount or time or a time that
/// follows the amount, then too few days.
int refusalRank(RefusalReason reason) => switch (reason) {
  RefusalReason.tooSmall => -1,
  RefusalReason.entangled => 0,
  RefusalReason.chance => 1,
  RefusalReason.uneven => 2,
  RefusalReason.oneDay => 3,
  RefusalReason.withinNoise => 4,
  RefusalReason.steadyAmount ||
  RefusalReason.steadyTiming ||
  RefusalReason.followsAmount ||
  RefusalReason.followsBedtime => 5,
  RefusalReason.tooFewDays => 6,
};

HabitRefusal _mostTelling(List<HabitRefusal> refusals) {
  return refusals.reduce((a, b) {
    final int byReason = refusalRank(a.reason).compareTo(refusalRank(b.reason));
    if (byReason != 0) return byReason < 0 ? a : b;
    final int byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind < 0 ? a : b;
    return b.usableDays > a.usableDays ? b : a;
  });
}

enum DirectionWords {
  moreLess,
  higherLower,

  /// "more pleasant", "less pleasant"; amounts and levels in words, never
  /// numbers ([measureAmount], [measureLevel]).
  pleasantness,
}

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

  /// Shown in words rather than numbers.
  bool get inWords => _words == DirectionWords.pleasantness;

  String direction(double effect) => switch (_words) {
    DirectionWords.moreLess => effect < 0 ? 'less' : 'more',
    DirectionWords.higherLower => effect < 0 ? 'lower' : 'higher',
    DirectionWords.pleasantness =>
      effect < 0 ? 'less pleasant' : 'more pleasant',
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
  'workoutMinutes' => const MetricCopy(
    'workout time',
    night: false,
    unit: 'min',
    words: DirectionWords.moreLess,
  ),
  'mindfulMinutes' => const MetricCopy(
    'mindful time',
    night: false,
    unit: 'min',
    words: DirectionWords.moreLess,
  ),
  'remindersCompleted' => const MetricCopy(
    'completed-reminder count',
    night: false,
    decimals: 1,
    words: DirectionWords.moreLess,
  ),
  'remindersMissed' => const MetricCopy(
    'missed-reminder count',
    night: false,
    decimals: 1,
    words: DirectionWords.moreLess,
  ),
  'moodValence' => const MetricCopy(
    'mood',
    night: false,
    words: DirectionWords.pleasantness,
  ),
  _ => null,
};

/// What a change the size of [metricId]'s floor has been shown to go with,
/// with its source in short (docs/insights/floors-literature.md); null for a
/// floor no source supports.
String? metricEvidence(String metricId) => switch (metricId) {
  'sleepAsleep' =>
    '21 min more sleep a night cut sugar eaten by about 10 g a day '
        '(Al Khatib 2018).',
  'sleepAwake' =>
    'Sleep medicine counts 20 min less awake in the night as a clinical '
        'change (AASM 2017).',
  'sleepREM' =>
    'Each 5% less of the night in REM went with 13% higher mortality '
        '(Leary 2020).',
  'heartRateVariabilitySDNN' =>
    'Easing training when HRV fell half a usual swing improved cyclists’ time '
        'trials 7% (Javaloyes 2019).',
  'restingHeartRate' =>
    'Each 5 bpm rise went with 12% higher mortality over 28 years '
        '(Vazir 2018).',
  'sleepingHeartRate' =>
    'Each 5 bpm rise in resting heart rate went with 12% higher mortality '
        '(Vazir 2018).',
  'oxygenSaturation' =>
    'Each point lower at night went with 33% more heart events, in dialysis '
        '(Zoccali 2002).',
  'stepCount' =>
    'Each 500 more steps a day went with 7% lower heart-disease death '
        '(Banach 2023).',
  'activeEnergyBurned' =>
    'About 85 kcal more a day (5 kJ per kg at 70 kg) went with 21% lower '
        'mortality (Strain 2020).',
  'workoutMinutes' =>
    'About 15 min of exercise a day went with 14% lower mortality than '
        'none (Wen 2011).',
  'mindfulMinutes' =>
    '13 min of meditation a day for 8 weeks lowered negative mood against a '
        'podcast (Basso 2019).',
  'moodValence' =>
    'Half your own day-to-day spread, after the usual rule that half a '
        'standard deviation is the smallest change people notice in rated '
        'wellbeing (Norman 2003).',
  _ => null,
};

/// [metricEvidence] for [finding]'s outcome; none for an hours-after one,
/// which sets minutes against the hour before rather than days or nights.
String? findingEvidence(HabitFinding finding) =>
    finding.kind == InsightKind.hoursAfter
    ? null
    : metricEvidence(finding.metricId);

MetricCopy _minutes(String name) =>
    MetricCopy(name, night: true, unit: 'min', words: DirectionWords.moreLess);

String _amount(double value, MetricCopy copy, int decimals, String locale) =>
    measureAmount(value, copy, decimals, locale);

/// The size of a difference of [value] in [copy]'s units: "18 min"; for a
/// measure shown in words, a size word on the mood scale, whose seven labels
/// in Health are 2/7 apart: under half a label "slightly", up to a label and
/// a half "noticeably", beyond it "much". The cut-offs are ours; no source
/// gives them.
String measureAmount(
  double value,
  MetricCopy copy,
  int decimals,
  String locale,
) {
  if (copy.inWords) {
    final double size = value.abs();
    return size < 1 / 7
        ? 'slightly'
        : size < 3 / 7
        ? 'noticeably'
        : 'much';
  }
  final String number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: decimals,
  ).format(value.abs() * copy.scale);
  return copy.unit.isEmpty ? number : '$number ${copy.unit}';
}

/// [value] as a level in [copy]'s units: "58 bpm"; for a measure shown in
/// words, the label Health gives that valence ("slightly pleasant"), its
/// seven equal bands from -1 to 1.
String measureLevel(
  double value,
  MetricCopy copy,
  int decimals,
  String locale,
) {
  if (copy.inWords) {
    const List<String> labels = <String>[
      'very unpleasant',
      'unpleasant',
      'slightly unpleasant',
      'neutral',
      'slightly pleasant',
      'pleasant',
      'very pleasant',
    ];
    return labels[((value + 1) * 3.5).floor().clamp(0, 6)];
  }
  final String number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: decimals,
  ).format(value * copy.scale);
  return copy.unit.isEmpty ? number : '$number ${copy.unit}';
}

// Enough digits that neither end of the range rounds to zero, since a finding's
// range never includes it.
int _digits(HabitFinding finding, MetricCopy copy) => _digitsToShow(
  min(finding.interval.low.abs(), finding.interval.high.abs()) * copy.scale,
  copy.decimals,
);

// [decimals], or more (up to 3) while [shown] would round to zero at them.
int _digitsToShow(double shown, int decimals) {
  int digits = decimals;
  while (digits < 3 && shown < 0.5 * pow(10, -digits)) {
    digits++;
  }
  return digits;
}

/// "On nights after Coffee, your deep sleep averages 18 min less."; for an
/// amount, "On days with one more drink logged for Coffee, your deep sleep
/// that night averages 6 min less."; for a time, "On days your last use of
/// Coffee is an hour later, ...". [unit] is the habit's, for an amount. The
/// habit's name only ever follows "after", "for" or "of", and no verb agrees
/// with it, so a plural or uncountable name (Gummies, Water) reads as well.
/// The effect is the whole of it; [bedtimeLine] gives the part left at the
/// same bedtime.
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
      'On days with ${stepWords(finding.step, unit, locale, more: true)} logged for '
          '$habit, your ${copy.name} $then averages $amount $direction.',
    InsightKind.lastUse =>
      'On days your last use of $habit is an hour later, your ${copy.name} '
          '$then averages $amount $direction.',
    InsightKind.hoursAfter =>
      '${_windowWords(finding.window!)} $habit, your ${copy.name}, set '
          'against the hour before, averages $amount $direction than at the '
          'same time after waking without it.',
    InsightKind.doseLine =>
      'On days with ${cutAmount(finding.cut!, unit, locale)} or more logged '
          'for $habit, your ${copy.name} $then averages $amount $direction '
          'than on days with fewer.',
    InsightKind.lastUseLine =>
      'On days your last use of $habit is at ${_cutClock(finding.cut!)} or '
          'later, your ${copy.name} $then averages $amount $direction than on '
          'days it is earlier.',
  };
}

/// A card's line under its headline: "More per extra drink: REM sleep 4 min
/// less", "Later last use: time asleep 11 min less per hour", and on the
/// minutes of sleep, the part left at the same bedtime after it (see
/// [bedtimeLine]).
String findingLine(
  HabitFinding finding,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final String change =
      '${copy.name} ${_amount(finding.effect, copy, _digits(finding, copy), locale)} '
      '${copy.direction(finding.effect)}';
  final String line = switch (finding.kind) {
    InsightKind.use => 'On ${copy.night ? 'nights' : 'days'} after it: $change',
    InsightKind.dose =>
      'More per extra ${stepWords(finding.step, unit, locale)}: $change',
    InsightKind.lastUse => 'Later last use: $change per hour',
    InsightKind.hoursAfter => '${_windowWords(finding.window!)} it: $change',
    InsightKind.doseLine =>
      'From ${cutAmount(finding.cut!, unit, locale)} a day: $change',
    InsightKind.lastUseLine =>
      'Last use at ${_cutClock(finding.cut!)} or later: $change',
  };
  final String? part = _bedtimePart(finding, copy, locale);
  return part == null ? line : '$line, $part';
}

/// Under an amount's or a time's headline on the minutes of sleep, the whole
/// effect and then the part of it left at the same bedtime: "11 min less per
/// hour later, 4 min of it at the same bedtime". Null only when the part was
/// never looked for ([HabitFinding.sameBedtime] null); a part that could not
/// be told still gets a line, so a sleep card never reads as if bedtime were
/// not in question.
String? bedtimeLine(
  HabitFinding finding,
  String locale, {
  Unit unit = Unit.fallback,
}) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  final String? part = _bedtimePart(finding, copy, locale);
  if (part == null) return null;
  final String per = switch (finding.kind) {
    InsightKind.lastUse => 'per hour later',
    InsightKind.doseLine =>
      'from ${cutAmount(finding.cut!, unit, locale)} a day',
    InsightKind.lastUseLine =>
      'with the last use at ${_cutClock(finding.cut!)} or later',
    _ => 'per extra ${stepWords(finding.step, unit, locale)}',
  };
  return '${_amount(finding.effect, copy, _digits(finding, copy), locale)} '
      '${copy.direction(finding.effect)} $per, $part';
}

// "4 min of it at the same bedtime" when the part is clear, on the same side
// and no larger; "2 min more at the same bedtime" when it is clear otherwise.
// A part refused before it was fitted (too few nights with a bedtime read,
// a steady amount or time among them, an uneven span, an entanglement) still
// says so: its headline is a sleep effect that bedtime may carry.
String? _bedtimePart(HabitFinding finding, MetricCopy copy, String locale) {
  switch (finding.sameBedtime) {
    case final HabitFinding part:
      final bool within =
          part.effect.sign == finding.effect.sign &&
          part.effect.abs() <= finding.effect.abs();
      return '${_amount(part.effect, copy, _digits(part, copy), locale)} '
          '${within ? 'of it' : copy.direction(part.effect)} at the same '
          'bedtime';
    case HabitRefusal(reason: RefusalReason.followsBedtime):
      return 'which can’t be told apart from your bedtime';
    case HabitRefusal(effect: _?):
      return 'none of it clear at the same bedtime';
    case HabitRefusal(reason: RefusalReason.tooFewDays):
      return 'too few nights with a bedtime to tell the part at the same '
          'bedtime';
    case HabitRefusal():
      return 'the part at the same bedtime can’t be told';
    case null:
      return null;
  }
}

// "3 drinks", "250 millilitres"; a count of times reads as uses.
String cutAmount(double cut, Unit unit, String locale) {
  final String word = unit == Unit.time
      ? pluralWord(cut, one: 'use', other: 'uses')
      : unit.nameFor(cut);
  return '${NumberFormat.decimalPattern(locale).format(cut)} $word';
}

// "15:00", on the dial's 24-hour clock; a cut past midnight belongs to the
// evening before, so it says which side of midnight it is.
String _cutClock(double cut) {
  final int minutes = cut.round();
  if (minutes == Duration.minutesPerDay) return 'midnight';
  final String clock =
      '${(minutes ~/ 60 % 24).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
  return minutes > Duration.minutesPerDay ? '$clock after midnight' : clock;
}

String _windowWords(HourWindow w) => switch ((w.start, w.end)) {
  (0, 30) => 'In the half hour after',
  (30, 60) => 'Half an hour to an hour after',
  (60, 120) => 'One to two hours after',
  (120, 240) => 'Two to four hours after',
  _ => '${w.start} to ${w.end} minutes after',
};

// "drink", "10 minutes"; with [more], "one more drink", "10 more minutes". A
// count of times reads as uses.
String stepWords(double step, Unit unit, String locale, {bool more = false}) {
  final String one = unit == Unit.time ? 'use' : unit.singular;
  final String other = unit == Unit.time ? 'uses' : unit.plural;
  final String word = more ? 'more ' : '';
  if (step == 1) return more ? 'one more $one' : one;
  final String number = NumberFormat.decimalPattern(locale).format(step);
  return '$number $word${pluralWord(step, one: one, other: other)}';
}

/// "18 min less": [finding]'s effect in its outcome's units and words.
String findingChange(HabitFinding finding, String locale) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  return '${_amount(finding.effect, copy, _digits(finding, copy), locale)} '
      '${copy.direction(finding.effect)}';
}

/// "Range: 7 to 29 min less"; both ends share a sign, so one word serves.
/// In words, "Range: slightly to noticeably less pleasant", or "Range:
/// noticeably less pleasant at both ends".
String findingRange(HabitFinding finding, String locale) {
  final MetricCopy copy = metricCopy(finding.metricId)!;
  if (copy.inWords) {
    final String low = measureAmount(
      min(finding.interval.low.abs(), finding.interval.high.abs()),
      copy,
      0,
      locale,
    );
    final String high = measureAmount(
      max(finding.interval.low.abs(), finding.interval.high.abs()),
      copy,
      0,
      locale,
    );
    final String direction = copy.direction(finding.effect);
    return low == high
        ? 'Range: $low $direction at both ends'
        : 'Range: $low to $high $direction';
  }
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
/// amount or a time, which compare days of use alone; for a line, "From 64
/// days with Coffee, 20 of them with 3 drinks or more".
String findingBasis(
  HabitFinding finding,
  String habit, {
  String locale = 'en',
  Unit unit = Unit.fallback,
}) {
  final String basis = switch (finding.kind) {
    InsightKind.doseLine =>
      'From ${finding.usableDays} days with $habit, '
          '${finding.exposedDays} of them with '
          '${cutAmount(finding.cut!, unit, locale)} or more',
    InsightKind.lastUseLine =>
      'From ${finding.usableDays} days with $habit, '
          '${finding.exposedDays} of them with the last use at '
          '${_cutClock(finding.cut!)} or later',
    InsightKind.hoursAfter =>
      'From ${finding.exposedDays} days with $habit, against '
          '${finding.usableDays - finding.exposedDays} days at the same time '
          'after waking with none of it within 4 hours'
          '${_stepWaking(finding)}',
    InsightKind.dose ||
    InsightKind.lastUse => 'From ${finding.usableDays} days with $habit',
    InsightKind.use => switch (finding.raw?.exposedDays) {
      null => 'From ${finding.usableDays} days',
      final int used =>
        'From ${finding.usableDays} days, $used of them with $habit',
    },
  };
  final bool phase = finding.heldFixed.contains(cyclePhaseId);
  final bool daylight = finding.heldFixed.contains(dayLengthId);
  return switch ((phase, daylight)) {
    (true, true) =>
      '$basis, compared within the same phase of your cycle and length of day',
    (true, false) => '$basis, compared within the same phase of your cycle',
    (false, true) => '$basis, compared at the same length of day',
    (false, false) => basis,
  };
}

String _stepWaking(HabitFinding finding) => switch (finding.stepWakingDays) {
  0 => '',
  final int n when n == finding.usableDays =>
    '; waking estimated from steps, with no night in Health',
  final int n =>
    '; waking estimated from steps on $n of these days, with no night in '
        'Health',
};

/// Why a habit has no finding, in plain words; for an amount or a time, said
/// to be about that.
String refusalReason(
  HabitRefusal refusal,
  String Function(String habitId) nameOf, {
  InsightGates gates = const InsightGates(),
  Map<String, double> floors = const <String, double>{},
}) => switch (refusal.kind) {
  InsightKind.use => _useRefusal(refusal, nameOf, gates, floors),
  InsightKind.dose =>
    'Amount: ${_amongUseRefusal(refusal, nameOf, gates, floors)}',
  InsightKind.lastUse =>
    'Time of last use: ${_amongUseRefusal(refusal, nameOf, gates, floors)}',
  InsightKind.hoursAfter =>
    'Hours after it: ${_hoursAfterRefusal(refusal, floors)}',
  InsightKind.doseLine =>
    'A line in the amount: ${_amongUseRefusal(refusal, nameOf, gates, floors)}',
  InsightKind.lastUseLine =>
    'A cut-off time for the last use: '
        '${_amongUseRefusal(refusal, nameOf, gates, floors)}',
};

String _hoursAfterRefusal(HabitRefusal refusal, Map<String, double> floors) {
  const HoursAfterGates gates = HoursAfterGates();
  final String name = metricCopy(refusal.metricId)?.name ?? 'Health';
  final String days = '${refusal.exposedDays} days of ${gates.minEventDays}';
  return switch (refusal.reason) {
    RefusalReason.tooFewDays => switch (refusal.shortfall) {
      HoursAfterShortfall.uses ||
      null => 'too few uses with none of it in the 4 hours before yet: $days',
      HoursAfterShortfall.noSleep =>
        'needs your sleep in Health, or steps through the morning, to time '
            'each use from waking: most uses have no night recorded before '
            'them',
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
    RefusalReason.tooSmall =>
      'too small to matter, ${_underFloor(refusal, floors)}',
    _ => 'within the noise, no clear difference',
  };
}

String _amongUseRefusal(
  HabitRefusal refusal,
  String Function(String habitId) nameOf,
  InsightGates gates,
  Map<String, double> floors,
) => switch (refusal.reason) {
  RefusalReason.tooFewDays =>
    'too few days with it yet: ${refusal.usableDays} of ${gates.minDays}',
  RefusalReason.steadyAmount =>
    'nearly the same each day, so there’s no difference to compare',
  RefusalReason.steadyTiming =>
    'nearly the same each day, so there’s no difference to compare',
  RefusalReason.followsAmount =>
    'later on days with more, so it can’t be told apart from the amount',
  // A HabitFinding.sameBedtime alone refuses so, and shows as a card line.
  RefusalReason.followsBedtime =>
    'moves with when you fall asleep, so it can’t be told apart from '
        'your bedtime',
  RefusalReason.uneven =>
    'changed with the months, so it can’t be told apart from other changes',
  RefusalReason.entangled => switch (refusal.entangledWith) {
    final String other =>
      'moves with the days of ${nameOf(other)}, so the two can’t be told '
          'apart',
    null => 'moves with other habits’ days, so they can’t be told apart',
  },
  RefusalReason.withinNoise => 'within the noise, no clear difference',
  RefusalReason.oneDay =>
    'rests on one unusual day, so it may not hold on the others',
  RefusalReason.chance => 'could be chance, one of many comparisons',
  // A line's difference is between its two sides as they are.
  RefusalReason.tooSmall
      when refusal.kind == InsightKind.doseLine ||
          refusal.kind == InsightKind.lastUseLine =>
    'too small to matter, ${_underFloor(refusal, floors)}',
  RefusalReason.tooSmall =>
    'too small to matter, ${_underFloor(refusal, floors)} across your usual '
        'range',
};

String _useRefusal(
  HabitRefusal refusal,
  String Function(String habitId) nameOf,
  InsightGates gates,
  Map<String, double> floors,
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
  RefusalReason.tooSmall =>
    'Too small to matter: ${_underFloor(refusal, floors)}',
  // Set only on an amount or a time.
  RefusalReason.steadyAmount || RefusalReason.steadyTiming =>
    'Nearly the same each day, so there’s no difference to compare',
  RefusalReason.followsAmount =>
    'Later on days with more, so it can’t be told apart from the amount',
  RefusalReason.oneDay =>
    'Rests on one unusual day, so it may not hold on the others',
  // Never reached, as in _amongUseRefusal.
  RefusalReason.followsBedtime =>
    'Moves with when you fall asleep, so it can’t be told apart from your '
        'bedtime',
};

// "under 22 min a night of REM sleep", "under 500 a day of step count". A
// person's floor (21.4 min, 0.35 ms) is rounded up at the digits shown, so
// "under" stays true of every refused finding and never reads "under 0".
String _underFloor(HabitRefusal refusal, Map<String, double> floors) =>
    underFloor(refusal.metricId, floors);

/// "under 22 min a night of REM sleep", as [refusalReason] says a difference
/// too small to matter on [metricId].
String underFloor(String metricId, Map<String, double> floors) {
  final MetricCopy copy = metricCopy(metricId)!;
  if (copy.inWords) {
    return 'under half your usual day-to-day swing in ${copy.name}';
  }
  final double shown = metricFloor(metricId, floors) * copy.scale;
  final int digits = _digitsToShow(shown, copy.decimals);
  final num scale = pow(10, digits);
  final String floor = NumberFormat.decimalPatternDigits(
    locale: 'en',
    decimalDigits: digits,
  ).format((shown * scale - 1e-9).ceil() / scale);
  final String unit = copy.unit.isEmpty ? '' : ' ${copy.unit}';
  final String per = switch (metricFloors[metricId]?.family) {
    MetricFamily.sleep => ' a night',
    MetricFamily.activity ||
    MetricFamily.mindfulness ||
    MetricFamily.reminders => ' a day',
    _ => '',
  };
  return 'under $floor$unit$per of ${copy.name}';
}
