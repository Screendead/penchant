import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/step_changes.dart';

/// When a result is reported rather than refused. The defaults are the idea
/// file's (`ideas/insights/insights-engine.md`), not tuned on data, except
/// the four for balance, checked against synthetic habits in
/// `tools/insights-calibration/`: evenly used ones, whether used on
/// independent days or in runs of days, are refused at most about 1% of the
/// time.
class InsightGates {
  const InsightGates({
    this.minDays = 21,
    this.minExposedDays = 7,
    this.minUnexposedDays = 7,
    this.maxVarianceInflation = 5,
    this.minPeriodDays = 10,
    this.minMixedPeriods = 2,
    this.maxUseRateRatio = 3,
    this.unevenSignificance = 0.01,
    this.level = 0.95,
    this.falseDiscoveryRate = 0.1,
    this.minAmountSpread = 0.1,
    this.minTimingSpreadMinutes = 30,
    this.maxCuts = 5,
    this.minSerialPairs = 14,
    this.maxSerialCorrelation = 0.9,
    this.bootstrapBlockDays = 7,
    this.bootstrapReplicates = 2000,
  });

  final int minDays;
  final int minExposedDays;
  final int minUnexposedDays;
  final double maxVarianceInflation;

  /// The fewest usable days a calendar month needs to be a period of its own.
  final int minPeriodDays;

  /// When a span holds more than one period, how many of them need days
  /// both with the habit and without it.
  final int minMixedPeriods;

  /// When a span is one period: how many times more often a habit may be
  /// used, or gone without, in one half of its span than in the other, unless
  /// the difference is within [unevenSignificance] of chance.
  final double maxUseRateRatio;
  final double unevenSignificance;
  final double level;

  /// Benjamini-Hochberg's q across every comparison in one report.
  final double falseDiscoveryRate;

  /// For the dose: the smallest standard deviation of the day totals, as a
  /// fraction of their mean. The days whose total is not the commonest one
  /// must also number [minExposedDays], so two amounts are enough when each
  /// has a week of days.
  final double minAmountSpread;

  /// For the time of the last use: the smallest standard deviation of it.
  /// The days an hour or more from its median must also number
  /// [minExposedDays].
  final int minTimingSpreadMinutes;

  /// For a line in the amount or a cut-off time: the most places it is looked
  /// for. The result is judged as that many comparisons.
  final int maxCuts;

  /// For a comparison whose rows are days: the fewest pairs of rows a day
  /// apart before a standard error is widened for how much neighbouring days
  /// resemble each other ([serialInflation]), and the most resemblance
  /// allowed for. More pairs than any comparison has turns the widening off.
  final int minSerialPairs;
  final double maxSerialCorrelation;

  /// For the same comparisons: a result whose t interval excludes zero must
  /// also have a [blockBootstrapInterval] over blocks of this many days that
  /// does. No replicates turns that off.
  final int bootstrapBlockDays;
  final int bootstrapReplicates;
}

/// [fit]'s coefficient [column] judged for rows that are [days] in order:
/// the fit with its standard error widened for neighbouring days that
/// resemble each other, the widening itself, and the block-bootstrap
/// interval a finding must also clear.
({LinearFit fit, double inflation, Interval? Function(double level) bootstrap})
judgeDays(
  List<List<double>> rows,
  List<double> y,
  LinearFit fit,
  int column,
  List<DateTime> days,
  InsightGates gates,
) {
  final List<int> at = <int>[
    for (final DateTime day in days) daysBetween(days.first, day),
  ];
  final Partialled parts = partialOut(rows, y, fit, column);
  final double inflation = serialInflation(
    parts,
    at,
    minPairs: gates.minSerialPairs,
    maxCorrelation: gates.maxSerialCorrelation,
  );
  return (
    fit: fit.judgedAs(inflation),
    inflation: inflation,
    bootstrap: (double level) => blockBootstrapInterval(
      parts,
      fit.coefficients[column],
      at,
      blockDays: gates.bootstrapBlockDays,
      replicates: gates.bootstrapReplicates,
      level: level,
    ),
  );
}

/// What a result compares.
enum InsightKind {
  /// Days with the habit against days without it.
  use,

  /// Among days with the habit, the day's total amount.
  dose,

  /// Among days with the habit, the clock time of its last use, a use before
  /// [lateUseCutoffHour] counting as the evening before.
  lastUse,

  /// A Health sample measure in [HabitInsight.window] after each use, against
  /// the hour before it, beyond the same change at that time on other days.
  hoursAfter,

  /// Among days with the habit, those whose total amount is at or over
  /// [HabitInsight.cut] against those under it.
  doseLine,

  /// Among days with the habit, those whose last use is at or after
  /// [HabitInsight.cut] against those where it is earlier.
  lastUseLine,
}

// The kinds whose column is 0 or 1, so an effect is one side's days against
// the other's.
bool _sides(InsightKind kind) =>
    kind == InsightKind.use ||
    kind == InsightKind.doseLine ||
    kind == InsightKind.lastUseLine;

/// Minutes after a use, from [start] up to [end].
typedef HourWindow = ({int start, int end});

/// Why an [InsightKind.hoursAfter] comparison had too few days: the cause
/// that left out the most moments.
enum HoursAfterShortfall {
  /// Too few uses clear of the habit in the 4 hours before.
  uses,

  /// No night's sleep recorded before the moment, so no time awake to match.
  noSleep,

  /// The hour before or the window touched sleep, waking included.
  nearSleep,

  /// Another habit was used from the hour before to the window's end.
  otherHabit,

  /// The habit again before the window's end.
  sameHabit,

  /// Under the readings needed before and after.
  readings,

  /// A walk in the hour before or the window.
  walk,

  /// Too few nearby moments clear of the habit to compare with.
  controls,
}

/// The outcome after days a habit was used against after days it was not,
/// with no other habit taken into account.
class Comparison {
  const Comparison({
    required this.exposedMean,
    required this.unexposedMean,
    required this.exposedDays,
    required this.unexposedDays,
    required this.interval,
  });

  final double exposedMean;
  final double unexposedMean;
  final int exposedDays;
  final int unexposedDays;

  /// A Welch interval for [difference].
  final Interval interval;

  double get difference => exposedMean - unexposedMean;
}

enum RefusalReason {
  /// Too few usable days, or too few days with or without the habit;
  /// [HabitInsight.exposedDays] says which. For a dose or a time of use, too
  /// few days with the habit.
  tooFewDays,

  /// Used far more in one half of a one-period span than in the other, in
  /// too few periods both with and without it, or so much in step with the
  /// time terms that the model cannot tell it from a drift or a change in the
  /// outcome over the same months.
  uneven,

  /// Used on so many of the same days as [HabitRefusal.entangledWith] that the
  /// two cannot be told apart.
  entangled,

  /// The adjusted interval includes zero, or the interval from redrawing
  /// the days in week-long blocks does; [HabitRefusal.interval] is the one
  /// that does.
  withinNoise,

  /// For [InsightKind.dose] or [InsightKind.lastUse] on a sleep outcome: the
  /// amount or time moves so closely with when sleep began that the two
  /// cannot be told apart.
  followsBedtime,

  /// For [InsightKind.dose] or [InsightKind.lastUse]: the adjusted interval
  /// excludes zero, but the fit without the day that pulls the effect
  /// furthest from zero does not.
  oneDay,

  /// For [InsightKind.dose]: the day totals barely vary.
  steadyAmount,

  /// For [InsightKind.lastUse]: the last use comes at nearly the same time
  /// each day.
  steadyTiming,

  /// For [InsightKind.lastUse]: the last use comes later by about as much as
  /// the day's amount is larger (uses spaced through an evening from a set
  /// start), so the time cannot be told apart from the amount.
  followsAmount,

  /// The adjusted interval excludes zero, but not by enough to stand out
  /// among every comparison in the report. Set by the report, never by
  /// [whatFollows].
  chance,

  /// Passed every other check, but the difference is under the outcome's
  /// smallest one worth showing. Set by the report, after [chance].
  tooSmall,
}

sealed class HabitInsight {
  const HabitInsight({
    required this.habitId,
    required this.metricId,
    required this.lagDays,
    required this.usableDays,
    required this.exposedDays,
    required this.raw,
    this.kind = InsightKind.use,
    this.step = 1,
    this.window,
    this.cut,
  });

  final String habitId;
  final String metricId;
  final int lagDays;
  final int usableDays;

  /// Of [usableDays], the days the habit was used: all of them for a dose or
  /// a time of use; for a line or a cut-off, the days at or over [cut].
  final int exposedDays;

  /// Null when either side has fewer than two days, and for a dose or a time
  /// of use.
  final Comparison? raw;
  final InsightKind kind;

  /// What one step of the habit is, which an effect and its interval are
  /// per: 1 for [InsightKind.use], an amount in the habit's unit for
  /// [InsightKind.dose], minutes for [InsightKind.lastUse].
  final double step;

  /// Set for [InsightKind.hoursAfter] alone.
  final HourWindow? window;

  /// For [InsightKind.doseLine], the amount in the habit's unit, and for
  /// [InsightKind.lastUseLine], the minutes after midnight (past 1440 after
  /// the next one), that splits the days of use. Null while none was chosen.
  final double? cut;
}

class HabitFinding extends HabitInsight {
  const HabitFinding({
    required super.habitId,
    required super.metricId,
    required super.lagDays,
    required super.usableDays,
    required super.exposedDays,
    required super.raw,
    super.kind,
    super.step,
    super.window,
    super.cut,
    required this.effect,
    required this.interval,
    required this.standardized,
    required this.pValue,
    this.spread,
    this.sameBedtime,
    this.heldFixed = const <String>{},
  });

  /// The outcome's difference after a day with the habit, or per [step] more
  /// of it, or per [step] later, holding every other habit's use that day
  /// fixed.
  final double effect;
  final Interval interval;

  /// The outcome's difference for one standard deviation of the habit's
  /// column (its use, amount or time) over the usable days, in units of the
  /// outcome's standard deviation; for [InsightKind.use], [effect] over that
  /// deviation alone, as a day with against a day without. For ranking.
  final double standardized;

  /// Two-sided, for [effect] being zero.
  final double pValue;

  /// For [InsightKind.dose] and [InsightKind.lastUse]: the interquartile
  /// range of the habit's column over the usable days, in its units (the
  /// amount, or minutes), so [effect] / [step] × [spread] is the difference
  /// across a typical spread of days. Null for the other kinds.
  final double? spread;

  /// For [InsightKind.dose] and [InsightKind.lastUse] on the minutes of sleep
  /// ([sleepMinutesIds]): the same comparison with bedtime ([sleepOnsetId])
  /// held fixed, per the same [step], so the part of [effect] that does not
  /// work by moving bedtime. A refusal when that part is unclear or bedtime
  /// moves too closely with the habit to hold; null when it was not run. It
  /// describes a finding already made, so it is not one of the report's
  /// comparisons.
  final HabitInsight? sameBedtime;

  /// The [DayCondition.id]s the comparison held fixed: its days were compared
  /// within each level of these.
  final Set<String> heldFixed;
}

class HabitRefusal extends HabitInsight {
  const HabitRefusal({
    required super.habitId,
    required super.metricId,
    required super.lagDays,
    required super.usableDays,
    required super.exposedDays,
    required super.raw,
    super.kind,
    super.step,
    super.window,
    super.cut,
    required this.reason,
    this.entangledWith,
    this.effect,
    this.interval,
    this.pValue,
    this.shortfall,
  });

  final RefusalReason reason;

  /// Set for [InsightKind.hoursAfter] with [RefusalReason.tooFewDays].
  final HoursAfterShortfall? shortfall;
  final String? entangledWith;
  final double? effect;
  final Interval? interval;

  /// Set with [effect]: the habit was fitted, so it counts among the
  /// report's comparisons.
  final double? pValue;
}

/// For each habit, what [metricId] looks like [lagDays] days after a day it was
/// used, against days it was not.
///
/// Each habit is judged over its own span, the days from its first use to its
/// last, clipped to [from] and [through] when given: the days before someone
/// started logging it, or after they stopped, are not days without it. A day
/// whose outcome is missing is left out. [HabitInsight.usableDays] counts the
/// days left in that habit's span.
///
/// Attribution: on those days, one least-squares model of the outcome on an
/// intercept, a linear trend over the span, a level for each period after the
/// first, and a 0/1 "used that day" indicator for the habit and for every
/// other habit that clears the sample gates there, so the coefficient is the
/// habit's difference with the others and the time held fixed, and a habit
/// that only rides along with another, or with a drift or a step in the
/// outcome, gets no credit. A period is a calendar month, merged into its
/// neighbour while it holds fewer than [InsightGates.minPeriodDays] usable
/// days; a span of one period gets a level for its second half instead. With
/// period levels, the habit's coefficient comes from days with and without it
/// within the same period, so a change in use between months, a cut-down or
/// faded logging, is not read as an effect. A lasting shift in the outcome
/// inside a month ([OutcomeSeries.shifts]) is a level of its own from its day
/// on, so a change in use at the same time is not read as one either; a shift
/// too small or too brief to find still can be.
/// Another habit counts as not used on the days outside its own span: that can
/// make its coefficient a proxy for time, but its coefficient is never the one
/// reported here.
///
/// Balance: a span of several periods in which fewer than
/// [InsightGates.minMixedPeriods] hold days both with and without the habit is
/// refused, since its coefficient would rest on a single month. A span of one
/// period (a month and fewer than [InsightGates.minPeriodDays] usable days
/// beside it) has no month to compare within, so a habit used, or gone without,
/// [InsightGates.maxUseRateRatio] times more often in one half of it than the
/// other is refused: once logging fades, the days between stray entries read as
/// days without it, and a change in the outcome over them would be pinned on
/// it. That guard sees only when the habit was logged, so it also refuses a
/// real, steep change in use.
///
/// Each result is judged alone, at [InsightGates.level]; across many habits
/// and outcomes some will clear it by chance, so a report runs every result
/// through [controlFalseDiscoveries].
List<HabitInsight> whatFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
  List<DayCondition> conditions = const <DayCondition>[],
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _whatFollowsOne(
        id,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
        conditions: conditions,
      ),
  ];
}

// Each habit's days from its first use to its last, clipped to [from] and
// [through], whose outcome [lagDays] later is known, with those outcomes.
({DateTime? start, DateTime? end}) _span(
  DateTime? first,
  DateTime? last,
  DateTime? from,
  DateTime? through,
) => (
  start: first == null || from == null || first.isAfter(from)
      ? first
      : startOfDay(from),
  end: last == null || through == null || last.isBefore(through)
      ? last
      : through,
);

// One habit's result being built: what every refusal and finding of it
// shares.
class _Judged {
  _Judged({
    required this.id,
    required this.metricId,
    required this.lagDays,
    required this.kind,
    required this.days,
    required this.y,
    required this.x,
    required this.exposed,
    required this.raw,
    this.step = 1,
    this.cut,
    this.shifts = const <DateTime>[],
    this.conditions = const <DayCondition>[],
  });

  final String id;
  final String metricId;
  final int lagDays;
  final InsightKind kind;
  final List<DateTime> days;
  final List<double> y;

  // When the outcome's level shifted, by the outcome's date.
  final List<DateTime> shifts;

  // Held fixed when there are enough days of each level ([_timeTerms]).
  final List<DayCondition> conditions;

  // The habit's column: 0/1 use, the day's amount, or minutes after midnight.
  final List<double> x;
  final int exposed;
  final Comparison? raw;
  double step;
  final double? cut;

  HabitRefusal refuse(
    RefusalReason reason, {
    String? entangledWith,
    double? effect,
    Interval? interval,
    double? pValue,
  }) => HabitRefusal(
    habitId: id,
    metricId: metricId,
    lagDays: lagDays,
    usableDays: days.length,
    exposedDays: exposed,
    raw: raw,
    kind: kind,
    step: step,
    cut: cut,
    reason: reason,
    entangledWith: entangledWith,
    effect: effect,
    interval: interval,
    pValue: pValue,
  );
}

List<double> _exposure(
  DailyHabitSeries habits,
  String habit,
  List<DateTime> days,
) => <double>[
  for (final DateTime day in days) habits.total(habit, day) > 0 ? 1 : 0,
];

bool _clearsSampleGates(List<double> x, InsightGates gates) {
  final int exposed = x.where((v) => v == 1).length;
  return exposed >= gates.minExposedDays &&
      x.length - exposed >= gates.minUnexposedDays;
}

// A habit refused for its sample never enters: a one-off use would absorb
// its day, cost a degree of freedom and inflate this habit's variance.
Map<String, List<double>> _otherHabits(
  String id,
  List<String> habitIds,
  DailyHabitSeries habits,
  List<DateTime> days,
  InsightGates gates,
) => <String, List<double>>{
  for (final String other in habitIds)
    if (other != id) other: _exposure(habits, other, days),
}..removeWhere((_, v) => !_clearsSampleGates(v, gates));

HabitInsight _whatFollowsOne(
  String id, {
  required List<String> habitIds,
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  required int lagDays,
  required DateTime? from,
  required DateTime? through,
  required InsightGates gates,
  required List<DayCondition> conditions,
}) {
  final (:DateTime? start, :DateTime? end) = _span(
    habits.firstUse(id),
    habits.lastUse(id),
    from,
    through,
  );
  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[];
  if (start != null && end != null) {
    for (final DateTime day in daysFrom(start, end)) {
      final double? value = outcomes.value(metricId, addDays(day, lagDays));
      if (value != null) {
        days.add(day);
        y.add(value);
      }
    }
  }
  final List<double> x = _exposure(habits, id, days);
  final _Judged judged = _Judged(
    id: id,
    metricId: metricId,
    lagDays: lagDays,
    kind: InsightKind.use,
    days: days,
    y: y,
    x: x,
    exposed: x.where((v) => v == 1).length,
    raw: _welch(x, y, gates.level),
    shifts: _shiftDates(outcomes, metricId),
    conditions: conditions,
  );

  if (days.length < gates.minDays || !_clearsSampleGates(x, gates)) {
    return judged.refuse(RefusalReason.tooFewDays);
  }
  final List<int> period = periodsOf(days, gates.minPeriodDays);
  // Halves by usable days, so each holds at least half of minDays.
  if (period.last == 0
      ? unevenHalves(x, days.length ~/ 2, gates)
      : _mixedPeriods(x, period) < gates.minMixedPeriods) {
    return judged.refuse(RefusalReason.uneven);
  }
  return _attribute(
    judged,
    period: period,
    others: _otherHabits(id, habitIds, habits, days, gates),
    gates: gates,
  );
}

/// The outcome, in clock minutes after the noon that opens the night, of when
/// a night's main sleep began (`HealthMetric.sleepOnset`).
const String sleepOnsetId = 'sleepOnset';

/// How far from the median onset of a comparison's days a night's
/// [sleepOnsetId] may be before that day is left out.
const int maxOnsetFromMedianMinutes = 6 * 60;

/// The sleep outcomes that are minutes of a night (`HealthMetric`'s sleep
/// minutes), for which [doseFollows] and [lastUseFollows] hold [sleepOnsetId]
/// fixed. With a set wake time, every minute later to bed is a minute less in
/// bed and some share of a minute less of each stage, so a habit used later
/// on the evenings bed comes later would be credited with that arithmetic.
const Set<String> sleepMinutesIds = <String>{
  'sleepInBed',
  'sleepAsleep',
  'sleepAwake',
  'sleepCore',
  'sleepDeep',
  'sleepREM',
};

/// For each habit, what [metricId] looks like [lagDays] days after a day it
/// was used, by how much it was used: among the days of its span (see
/// [whatFollows]) that it was used, the day's total as the habit's column of
/// the same model, so a habit used every day still has days to compare. The
/// day is the one [lateDayOf] gives, so an entry after midnight adds to the
/// evening before it, as in [lastUseFollows]; [whatFollows] still counts it
/// on its calendar day. [HabitInsight.step] is the amount the effect is per:
/// one of the habit's unit, or for totals spread more widely than 3 units
/// (minutes, say) or narrowly than half of one, the largest 1, 2 or 5 times a
/// power of ten within one standard deviation of them, never under one when
/// every total is a whole number.
///
/// A result that one day decides is refused as [RefusalReason.oneDay]: the
/// fit without the day that pulls the effect furthest from zero must still
/// exclude zero.
///
/// The effect is the whole of it, bedtime included. For the minutes of sleep
/// ([sleepMinutesIds]), a finding also carries the part left at the same
/// bedtime ([HabitFinding.sameBedtime]): the same model with the time sleep
/// began that night ([sleepOnsetId]) in it, over the days with an onset
/// inside 0 to 1440 and within [maxOnsetFromMedianMinutes] of their median,
/// refused as [RefusalReason.followsBedtime] when the amount moves so closely
/// with bedtime that the two cannot be told apart. When [outcomes] hold no
/// [sleepOnsetId], there is no such part.
///
/// Refused as [RefusalReason.steadyAmount] when the totals barely vary (see
/// [InsightGates.minAmountSpread]), and as [RefusalReason.uneven] when
/// they changed so much with the months, or so little within them, that the
/// time terms leave them nothing of their own. As with [whatFollows], a
/// change in amount and in the outcome inside one month can still be read as
/// an effect.
List<HabitInsight> doseFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
  List<DayCondition> conditions = const <DayCondition>[],
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _amongDaysOfUse(
        id,
        kind: InsightKind.dose,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
        conditions: conditions,
      ),
  ];
}

/// As [doseFollows], with the clock time of the day's last use for the
/// habit's column, in minutes after midnight, and a use before
/// [lateUseCutoffHour] counted as a late use of the day before
/// ([lateDayOf]). [HabitInsight.step] is 60, so an effect is per hour later.
/// The day's total amount (over the same uses) is in the model too when it
/// varies, so a later finish is not credited with what a larger amount does.
/// For the minutes of sleep, a finding carries the part left at the same
/// bedtime, as for [doseFollows].
///
/// Refused as [RefusalReason.steadyTiming] when the last use comes at nearly
/// the same time each day ([InsightGates.minTimingSpreadMinutes]), and as
/// [RefusalReason.followsAmount] when it moves so closely with the day's
/// amount that the two cannot be told apart.
List<HabitInsight> lastUseFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
  List<DayCondition> conditions = const <DayCondition>[],
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _amongDaysOfUse(
        id,
        kind: InsightKind.lastUse,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
        conditions: conditions,
      ),
  ];
}

/// For each habit, where the line is in its amount: among the days of its
/// span it was used (as [doseFollows], on the day [lateDayOf] gives), the days
/// whose total is at or over [HabitInsight.cut] against those under it, as the
/// habit's 0/1 column of the same model. The effect is the difference between
/// the two sides, not a claim that nothing changes under the line.
///
/// The cut is looked for on a grid fixed by the amounts alone: every multiple
/// of [doseFollows]' step with [InsightGates.minExposedDays] days at or over
/// it and [InsightGates.minUnexposedDays] under, thinned evenly to
/// [InsightGates.maxCuts]. The one that explains most of the outcome is
/// reported, and judged as if every cut on the grid had been tested
/// (Bonferroni): its interval is at 1 - (1 - [InsightGates.level]) / cuts and
/// its p-value is multiplied by the cuts, so picking the best-looking cut
/// buys no findings on noise.
///
/// Refused as [RefusalReason.steadyAmount] when no cut leaves enough days on
/// each side. For the minutes of sleep, a finding carries the part left at
/// the same bedtime, at the same cut.
List<HabitInsight> doseLineFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
  List<DayCondition> conditions = const <DayCondition>[],
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _amongDaysOfUse(
        id,
        kind: InsightKind.doseLine,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
        conditions: conditions,
      ),
  ];
}

/// As [doseLineFollows], for the clock time of the day's last use (as
/// [lastUseFollows], with the day's amount held fixed): the days it comes at
/// or after [HabitInsight.cut] against the days it comes earlier, the cut
/// looked for on the whole hours.
List<HabitInsight> lastUseLineFollows({
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  int lagDays = 1,
  DateTime? from,
  DateTime? through,
  InsightGates gates = const InsightGates(),
  List<DayCondition> conditions = const <DayCondition>[],
}) {
  final List<String> habitIds = habits.habitIds.toList()..sort();
  return <HabitInsight>[
    for (final String id in habitIds)
      _amongDaysOfUse(
        id,
        kind: InsightKind.lastUseLine,
        habitIds: habitIds,
        habits: habits,
        outcomes: outcomes,
        metricId: metricId,
        lagDays: lagDays,
        from: from,
        through: through,
        gates: gates,
        conditions: conditions,
      ),
  ];
}

HabitInsight _amongDaysOfUse(
  String id, {
  required InsightKind kind,
  required List<String> habitIds,
  required DailyHabitSeries habits,
  required OutcomeSeries outcomes,
  required String metricId,
  required int lagDays,
  required DateTime? from,
  required DateTime? through,
  required InsightGates gates,
  required List<DayCondition> conditions,
}) {
  final bool timing =
      kind == InsightKind.lastUse || kind == InsightKind.lastUseLine;
  final List<DateTime> useDays = habits.lateDays(id).toList()..sort();
  final (:DateTime? start, :DateTime? end) = _span(
    useDays.firstOrNull,
    useDays.lastOrNull,
    from,
    through,
  );
  final bool bedtime =
      sleepMinutesIds.contains(metricId) &&
      outcomes.metricIds.contains(sleepOnsetId);
  final List<DateTime> days = <DateTime>[];
  final List<double> y = <double>[], x = <double>[], amount = <double>[];
  final List<double?> onset = <double?>[];
  for (final DateTime day in useDays) {
    if (start == null || end == null) break;
    if (day.isBefore(start) || day.isAfter(end)) continue;
    final double? value = outcomes.value(metricId, addDays(day, lagDays));
    if (value == null) continue;
    days.add(day);
    y.add(value);
    amount.add(habits.lateDayTotal(id, day));
    x.add(timing ? habits.lastUseMinutes(id, day)!.toDouble() : amount.last);
    if (bedtime) {
      onset.add(outcomes.value(sleepOnsetId, addDays(day, lagDays)));
    }
  }
  _Judged judgedOn(List<int> rows, double step) => _Judged(
    id: id,
    metricId: metricId,
    lagDays: lagDays,
    kind: kind,
    days: <DateTime>[for (final int r in rows) days[r]],
    y: <double>[for (final int r in rows) y[r]],
    x: <double>[for (final int r in rows) x[r]],
    exposed: rows.length,
    raw: null,
    step: step,
    shifts: _shiftDates(outcomes, metricId),
    conditions: conditions,
  );
  final List<int> all = <int>[for (int r = 0; r < days.length; r++) r];
  final HabitInsight total = _amongDaysJudged(
    judgedOn(all, kind == InsightKind.lastUse ? 60 : 1),
    amount: amount,
    habitIds: habitIds,
    habits: habits,
    gates: gates,
    pickStep: kind == InsightKind.dose,
  );
  if (!bedtime || total is! HabitFinding) return total;
  final List<int> usual = _usualOnsets(onset);
  final HabitInsight held = _amongDaysJudged(
    judgedOn(usual, total.step),
    amount: <double>[for (final int r in usual) amount[r]],
    onset: <double>[for (final int r in usual) onset[r]!],
    habitIds: habitIds,
    habits: habits,
    gates: gates,
    pickStep: false,
    cut: total.cut,
  );
  return HabitFinding(
    habitId: total.habitId,
    metricId: total.metricId,
    lagDays: total.lagDays,
    usableDays: total.usableDays,
    exposedDays: total.exposedDays,
    raw: total.raw,
    kind: total.kind,
    step: total.step,
    cut: total.cut,
    effect: total.effect,
    interval: total.interval,
    standardized: total.standardized,
    pValue: total.pValue,
    spread: total.spread,
    sameBedtime: held,
    heldFixed: total.heldFixed,
  );
}

// The rows of [onset] that read as a night's bedtime: present, inside the
// noon-to-noon night it is read in, and within [maxOnsetFromMedianMinutes] of
// the median of those. One misread or nap held fixed would carry the fit.
List<int> _usualOnsets(List<double?> onset) {
  final List<int> read = <int>[
    for (int r = 0; r < onset.length; r++)
      if (onset[r] case final double v when v >= 0 && v <= 24 * 60) r,
  ];
  if (read.isEmpty) return read;
  final List<double> sorted = <double>[for (final int r in read) onset[r]!]
    ..sort();
  final double median = sorted[sorted.length ~/ 2];
  return <int>[
    for (final int r in read)
      if ((onset[r]! - median).abs() <= maxOnsetFromMedianMinutes) r,
  ];
}

// The gates and the model for an amount or a time over [judged]'s days, with
// [amount] (for a time) and [onset] held fixed when they vary. With
// [pickStep], an amount's step is chosen from its spread here. A line or a
// cut-off is looked for unless [cut] gives it.
HabitInsight _amongDaysJudged(
  _Judged judged, {
  required List<double> amount,
  List<double>? onset,
  required List<String> habitIds,
  required DailyHabitSeries habits,
  required InsightGates gates,
  required bool pickStep,
  double? cut,
}) {
  final bool timing =
      judged.kind == InsightKind.lastUse ||
      judged.kind == InsightKind.lastUseLine;
  final List<DateTime> days = judged.days;
  final List<double> x = judged.x;
  if (days.length < gates.minDays) {
    return judged.refuse(RefusalReason.tooFewDays);
  }
  final double sd = sqrt(sampleVariance(x));
  if (timing) {
    final List<double> sorted = x.toList()..sort();
    final double median = sorted[sorted.length ~/ 2];
    final int away = x.where((v) => (v - median).abs() >= 60).length;
    if (sd < gates.minTimingSpreadMinutes || away < gates.minExposedDays) {
      return judged.refuse(RefusalReason.steadyTiming);
    }
  } else {
    final Map<double, int> counts = <double, int>{};
    for (final double v in x) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final int commonest = counts.values.reduce(max);
    if (x.length - commonest < gates.minExposedDays ||
        sd < gates.minAmountSpread * mean(x)) {
      return judged.refuse(RefusalReason.steadyAmount);
    }
    if (pickStep) {
      judged.step = doseStep(sd, whole: x.every((v) => v == v.roundToDouble()));
    }
  }
  final List<int> period = periodsOf(days, gates.minPeriodDays);
  final List<_Own> own = <_Own>[
    if (timing && sampleVariance(amount) > 0)
      (column: amount, reason: RefusalReason.followsAmount),
    if (onset != null && sampleVariance(onset) > 0)
      (column: onset, reason: RefusalReason.followsBedtime),
  ];
  if (!_sides(judged.kind)) {
    if (period.last > 0 && _varyingPeriods(x, period) < gates.minMixedPeriods) {
      return judged.refuse(RefusalReason.uneven);
    }
    return _attribute(
      judged,
      period: period,
      others: _otherHabits(judged.id, habitIds, habits, days, gates),
      own: own,
      gates: gates,
    );
  }
  final List<double> cuts = cut != null
      ? <double>[cut]
      : _cuts(
          x,
          timing
              ? 60
              : doseStep(sd, whole: x.every((v) => v == v.roundToDouble())),
          gates,
        );
  if (cuts.isEmpty) {
    return judged.refuse(
      timing ? RefusalReason.steadyTiming : RefusalReason.steadyAmount,
    );
  }
  final double at = cuts.length == 1
      ? cuts.single
      : _clearestCut(
          cuts,
          x,
          judged.y,
          _timeTerms(judged, period, gates).terms,
          own,
        );
  final List<double> over = <double>[for (final double v in x) v >= at ? 1 : 0];
  final _Judged sides = _Judged(
    id: judged.id,
    metricId: judged.metricId,
    lagDays: judged.lagDays,
    kind: judged.kind,
    days: days,
    y: judged.y,
    x: over,
    exposed: over.where((v) => v == 1).length,
    raw: null,
    cut: at,
    shifts: judged.shifts,
    conditions: judged.conditions,
  );
  // Only a cut handed in can fail this: the grid's all pass.
  if (!_clearsSampleGates(over, gates)) {
    return sides.refuse(RefusalReason.tooFewDays);
  }
  if (period.last > 0 && _mixedPeriods(over, period) < gates.minMixedPeriods) {
    return sides.refuse(RefusalReason.uneven);
  }
  return _attribute(
    sides,
    period: period,
    others: _otherHabits(judged.id, habitIds, habits, days, gates),
    own: own,
    gates: gates,
    searched: cuts.length,
  );
}

// Where a line may be drawn through [x]: the multiples of [grid] with enough
// days on each side, thinned evenly to [InsightGates.maxCuts]. From [x]
// alone, never the outcome, so their number is fixed before any is tried.
List<double> _cuts(List<double> x, double grid, InsightGates gates) {
  final List<double> sorted = x.toList()..sort();
  final int under = gates.minUnexposedDays, over = gates.minExposedDays;
  if (sorted.length < under + over || under < 1 || over < 1) {
    return const <double>[];
  }
  // Rounded so a multiple of 0.1 is the amount logged, not a digit past it.
  double multiple(double k) => (k * grid * 1e9).roundToDouble() / 1e9;
  final List<double> cuts = <double>[];
  for (
    double k = (sorted[under - 1] / grid).floorToDouble();
    multiple(k) <= sorted[sorted.length - over];
    k++
  ) {
    if (multiple(k) > sorted[under - 1]) cuts.add(multiple(k));
  }
  final int keep = gates.maxCuts;
  if (cuts.length <= keep) return cuts;
  if (keep == 1) return <double>[cuts[cuts.length ~/ 2]];
  return <double>[
    for (int i = 0; i < keep; i++)
      cuts[(i * (cuts.length - 1) / (keep - 1)).round()],
  ];
}

// The cut of [cuts] whose 0/1 column explains most of [y] once the intercept,
// [time] and [own] are taken out of both (the largest squared correlation of
// the residuals); the middle one when those columns cannot be solved.
double _clearestCut(
  List<double> cuts,
  List<double> x,
  List<double> y,
  List<List<double>> time,
  List<_Own> own,
) {
  final List<List<double>> rows = <List<double>>[
    for (int r = 0; r < x.length; r++)
      <double>[1, ...time[r], for (final _Own o in own) o.column[r]],
  ];
  final List<List<double>>? inverse = invert(gram(rows));
  if (inverse == null) return cuts[cuts.length ~/ 2];
  final int p = rows.first.length;
  List<double> residual(List<double> v) {
    final List<double> xtv = List<double>.filled(p, 0);
    for (int r = 0; r < rows.length; r++) {
      for (int j = 0; j < p; j++) {
        xtv[j] += rows[r][j] * v[r];
      }
    }
    final List<double> beta = List<double>.filled(p, 0);
    for (int i = 0; i < p; i++) {
      for (int j = 0; j < p; j++) {
        beta[i] += inverse[i][j] * xtv[j];
      }
    }
    return <double>[
      for (int r = 0; r < rows.length; r++)
        () {
          double fitted = 0;
          for (int j = 0; j < p; j++) {
            fitted += rows[r][j] * beta[j];
          }
          return v[r] - fitted;
        }(),
    ];
  }

  final List<double> ry = residual(y);
  double best = cuts[cuts.length ~/ 2], most = 0;
  for (final double cut in cuts) {
    final List<double> rx = residual(<double>[
      for (final double v in x) v >= cut ? 1 : 0,
    ]);
    double xy = 0, xx = 0;
    for (int r = 0; r < rx.length; r++) {
      xy += rx[r] * ry[r];
      xx += rx[r] * rx[r];
    }
    if (xx > 1e-9 && xy * xy / xx > most) {
      most = xy * xy / xx;
      best = cut;
    }
  }
  return best;
}

// A fraction of a whole-number unit is an amount nobody logged.
double doseStep(double sd, {required bool whole}) {
  if (sd >= 0.5 && sd <= 3 || whole && sd < 0.5) return 1;
  double step = pow(10, (log(sd) / ln10).floor()).toDouble();
  for (final int m in <int>[5, 2]) {
    if (step * m <= sd) return step * m;
  }
  return step;
}

// Whether [fit]'s interval for [column] crosses zero once the day that pulls
// it furthest from zero is left out, by its DFBETA, (X'X)^-1 x_i e_i /
// (1 - h_i), the change that day makes to the coefficients. [inflation] is
// the widening [fit] already carries, given to the fit without that day too.
bool withoutMostTelling(
  List<List<double>> rows,
  List<double> y,
  LinearFit fit,
  int column,
  double level, {
  double inflation = 1,
}) {
  final List<List<double>> a = fit.inverseGram;
  final double sign = fit.coefficients[column].sign;
  int most = 0;
  double largest = double.negativeInfinity;
  for (int r = 0; r < rows.length; r++) {
    final List<double> row = rows[r];
    double fitted = 0, leverage = 0, toward = 0;
    for (int i = 0; i < row.length; i++) {
      fitted += row[i] * fit.coefficients[i];
      double ai = 0;
      for (int j = 0; j < row.length; j++) {
        ai += a[i][j] * row[j];
      }
      leverage += row[i] * ai;
      if (i == column) toward = ai;
    }
    final double pull = sign * toward * (y[r] - fitted) / (1 - leverage);
    if (pull > largest) {
      largest = pull;
      most = r;
    }
  }
  // A day worth less than one standard error of the effect is ordinary
  // weight: leaving out the strongest of many such days only costs power.
  if (largest < fit.standardError(column)) return false;
  final LinearFit? without = fitLeastSquares(
    <List<double>>[...rows.sublist(0, most), ...rows.sublist(most + 1)],
    <double>[...y.sublist(0, most), ...y.sublist(most + 1)],
  );
  return without == null ||
      without.judgedAs(inflation).interval(column, level: level).crossesZero;
}

// Periods in which the habit's column takes more than one value.
int _varyingPeriods(List<double> x, List<int> period) {
  final Map<int, Set<double>> seen = <int, Set<double>>{};
  for (int r = 0; r < x.length; r++) {
    seen.putIfAbsent(period[r], () => <double>{}).add(x[r]);
  }
  return seen.values.where((s) => s.length > 1).length;
}

// A column held fixed beside the habit's own (its amount, or bedtime), and
// the refusal when the habit's column cannot be told apart from it.
typedef _Own = ({List<double> column, RefusalReason reason});

// One least-squares model of the outcome on an intercept, the habit's
// column, the time terms, [own] and the other habits' use, and the habit's
// coefficient judged.
HabitInsight _attribute(
  _Judged judged, {
  required List<int> period,
  required Map<String, List<double>> others,
  List<_Own> own = const <_Own>[],
  required InsightGates gates,
  int searched = 1,
}) {
  final List<DateTime> days = judged.days;
  final List<double> x = judged.x, y = judged.y;
  final (terms: List<List<double>> time, held: Set<String> heldFixed) =
      _timeTerms(judged, period, gates);
  // Bonferroni over the cuts tried, for the interval and so for every gate
  // that reads it.
  final double level = 1 - (1 - gates.level) / searched;

  int exposedCount(String other) => others[other]!.where((v) => v == 1).length;
  final List<String> covariates = others.keys.toList()
    ..sort((a, b) {
      final int byUse = exposedCount(b).compareTo(exposedCount(a));
      return byUse != 0 ? byUse : a.compareTo(b);
    });

  List<List<double>> design(List<String> ids, {required List<_Own> held}) =>
      <List<double>>[
        for (int r = 0; r < days.length; r++)
          <double>[
            1,
            x[r],
            ...time[r],
            for (final _Own o in held) o.column[r],
            for (final String other in ids) others[other]![r],
          ],
      ];
  // Whether a design stays solvable without the habit's column: a column
  // that only duplicates those already in changes nothing this habit's
  // coefficient can see.
  bool addsSomething(List<List<double>> rows) =>
      invert(
        gram(<List<double>>[
          for (final List<double> row in rows) <double>[row[0], ...row.skip(2)],
        ]),
      ) !=
      null;

  // With an intercept in the model, (X'X)^-1 at j is 1 / (SS_j (1 - R_j^2)),
  // so this is 1 / (1 - R_j^2).
  final double mx = mean(x);
  final double ss = x.fold<double>(0, (s, v) => s + (v - mx) * (v - mx));
  double inflation(List<String> ids, {required List<_Own> held}) =>
      (invert(gram(design(ids, held: held)))?[1][1] ?? double.infinity) * ss;
  if (inflation(const <String>[], held: const <_Own>[]) >
      gates.maxVarianceInflation) {
    return judged.refuse(RefusalReason.uneven);
  }
  final List<_Own> held = <_Own>[];
  for (final _Own o in own) {
    if (!addsSomething(design(const <String>[], held: <_Own>[...held, o]))) {
      continue;
    }
    held.add(o);
    // What came before passed, so what inflates the column now is [o].
    if (inflation(const <String>[], held: held) > gates.maxVarianceInflation) {
      return judged.refuse(o.reason);
    }
  }
  final int fixedColumns = time.first.length + held.length;

  // Covariates join the most used first; one more column than would leave a
  // residual degree of freedom is skipped.
  final List<String> inModel = <String>[];
  for (final String other in covariates) {
    if (inModel.length + fixedColumns + 4 > days.length) break;
    if (addsSomething(design(<String>[...inModel, other], held: held))) {
      inModel.add(other);
    }
  }
  // The habit whose leaving out frees the column most; the time terms and
  // [held] alone were checked above, so one of [inModel] is the cause.
  String? partner() {
    String? best;
    double lowest = double.infinity;
    for (final String other in inModel) {
      final double v = inflation(<String>[
        for (final String id in inModel)
          if (id != other) id,
      ], held: held);
      if (best == null || v < lowest) {
        lowest = v;
        best = other;
      }
    }
    return best;
  }

  final List<List<double>> rows = design(inModel, held: held);
  if (invert(gram(rows)) == null) {
    return judged.refuse(RefusalReason.entangled, entangledWith: partner());
  }

  final LinearFit? fitted = fitLeastSquares(rows, y);
  if (fitted == null) return judged.refuse(RefusalReason.tooFewDays);
  const int column = 1;
  final (
    :LinearFit fit,
    inflation: double widening,
    :Interval? Function(double level) bootstrap,
  ) = judgeDays(
    rows,
    y,
    fitted,
    column,
    days,
    gates,
  );
  final double step = judged.step;
  final double effect = fit.coefficients[column] * step;
  final Interval perUnit = fit.interval(column, level: level);
  final Interval interval = Interval(perUnit.low * step, perUnit.high * step);
  final double pValue = min(1.0, searched * fit.pValue(column));
  if (fit.inverseGram[column][column] * ss > gates.maxVarianceInflation) {
    return judged.refuse(
      RefusalReason.entangled,
      entangledWith: partner(),
      effect: effect,
      interval: interval,
      pValue: pValue,
    );
  }
  if (interval.crossesZero) {
    return judged.refuse(
      RefusalReason.withinNoise,
      effect: effect,
      interval: interval,
      pValue: pValue,
    );
  }
  // A use comparison has a week of days on each side; an amount or a time
  // can hang on one extreme day.
  if (judged.kind != InsightKind.use &&
      withoutMostTelling(rows, y, fit, column, level, inflation: widening)) {
    return judged.refuse(
      RefusalReason.oneDay,
      effect: effect,
      interval: interval,
      pValue: pValue,
    );
  }
  final Interval? redrawn = bootstrap(level);
  if (redrawn != null && redrawn.crossesZero) {
    return judged.refuse(
      RefusalReason.withinNoise,
      effect: effect,
      interval: Interval(redrawn.low * step, redrawn.high * step),
      pValue: pValue,
    );
  }
  final double sd = sqrt(sampleVariance(y));
  final double perDeviation = _sides(judged.kind)
      ? fit.coefficients[column]
      : fit.coefficients[column] * sqrt(sampleVariance(x));
  return HabitFinding(
    habitId: judged.id,
    metricId: judged.metricId,
    lagDays: judged.lagDays,
    usableDays: days.length,
    exposedDays: judged.exposed,
    raw: judged.raw,
    kind: judged.kind,
    step: step,
    cut: judged.cut,
    effect: effect,
    interval: interval,
    standardized: sd == 0 ? 0 : perDeviation / sd,
    pValue: pValue,
    spread: _sides(judged.kind) ? null : interquartileRange(x),
    heldFixed: heldFixed,
  );
}

/// The p-value [insight] brings to the report's family; null when nothing was
/// fitted.
double? insightPValue(HabitInsight insight) => switch (insight) {
  HabitFinding(:final double pValue) => pValue,
  HabitRefusal(:final double? pValue) => pValue,
};

List<DateTime> _shiftDates(OutcomeSeries outcomes, String metricId) =>
    <DateTime>[
      for (final LevelShift s in outcomes.shifts(metricId).shifts) s.at,
    ];

// A linear trend over the span, then a level for each period after the first,
// or for the second half of a span of one period, then a level from each of
// the outcome's shifts on. A shift joins only with
// [InsightGates.minExposedDays] of the days on each side of it, and only
// while the terms stay solvable: one at a month's edge repeats that month's
// level. Then each of [_Judged.conditions] whose every level is on
// [InsightGates.minExposedDays] of the outcome's days: a level for each but
// the first, and one for the days of none, so days are compared within a
// level, while the terms stay solvable. Which conditions joined is [held].
({List<List<double>> terms, Set<String> held}) _timeTerms(
  _Judged judged,
  List<int> period,
  InsightGates gates,
) {
  final List<DateTime> days = judged.days;
  final int periods = period.last + 1;
  final int half = days.length ~/ 2;
  final int span = max(1, daysBetween(days.first, days.last));
  final List<List<double>> terms = <List<double>>[
    for (int r = 0; r < days.length; r++)
      <double>[
        daysBetween(days.first, days[r]) / span - 0.5,
        if (periods == 1)
          r < half ? 0 : 1
        else
          for (int k = 1; k < periods; k++) period[r] == k ? 1 : 0,
      ],
  ];
  for (final DateTime shift in judged.shifts) {
    final List<double> after = <double>[
      for (final DateTime day in days)
        addDays(day, judged.lagDays).isBefore(shift) ? 0 : 1,
    ];
    final int on = after.where((v) => v == 1).length;
    if (on < gates.minExposedDays || days.length - on < gates.minExposedDays) {
      continue;
    }
    final List<List<double>> wider = <List<double>>[
      for (int r = 0; r < days.length; r++) <double>[...terms[r], after[r]],
    ];
    final bool solvable =
        invert(
          gram(<List<double>>[
            for (final List<double> row in wider) <double>[1, ...row],
          ]),
        ) !=
        null;
    if (!solvable) continue;
    for (int r = 0; r < days.length; r++) {
      terms[r] = wider[r];
    }
  }
  final Set<String> held = <String>{};
  for (final DayCondition condition in judged.conditions) {
    if (condition.isMeasure) {
      final List<double>? column = _measureColumn(
        condition,
        judged,
        terms,
        gates,
      );
      if (column == null) continue;
      for (int r = 0; r < days.length; r++) {
        terms[r] = <double>[...terms[r], column[r]];
      }
      held.add(condition.id);
      continue;
    }
    final List<int?> level = <int?>[
      for (final DateTime day in days)
        condition.level(addDays(day, judged.lagDays)),
    ];
    final List<int> counts = List<int>.filled(condition.levels, 0);
    for (final int? l in level) {
      if (l != null) counts[l]++;
    }
    if (counts.any((int n) => n < gates.minExposedDays)) continue;
    final bool unknown = level.contains(null);
    final List<List<double>> wider = <List<double>>[
      for (int r = 0; r < days.length; r++)
        <double>[
          ...terms[r],
          for (int k = 1; k < condition.levels; k++) level[r] == k ? 1 : 0,
          if (unknown) level[r] == null ? 1 : 0,
        ],
    ];
    final bool solvable =
        invert(
          gram(<List<double>>[
            for (final List<double> row in wider) <double>[1, ...row],
          ]),
        ) !=
        null;
    if (!solvable) continue;
    for (int r = 0; r < days.length; r++) {
      terms[r] = wider[r];
    }
    held.add(condition.id);
  }
  return (terms: terms, held: held);
}

// A measure condition's column, centred, when every day has a value and it
// adds what [terms] miss: its own inflation against them, and the habit's
// column's beside them all, within [InsightGates.maxVarianceInflation], so
// holding it never turns a comparison into a refusal by itself. Day length
// over a span of months is nearly all month levels and trend, so it seldom
// joins there.
List<double>? _measureColumn(
  DayCondition condition,
  _Judged judged,
  List<List<double>> terms,
  InsightGates gates,
) {
  final List<double> raw = <double>[];
  for (final DateTime day in judged.days) {
    final double? v = condition.value(addDays(day, judged.lagDays));
    if (v == null) return null;
    raw.add(v);
  }
  final double m = mean(raw);
  final List<double> column = <double>[for (final double v in raw) v - m];
  double squares(List<double> v) {
    final double mv = mean(v);
    return v.fold<double>(0, (s, e) => s + (e - mv) * (e - mv));
  }

  final double ss = squares(column);
  if (ss < 1e-9) return null;
  final List<List<double>>? own = invert(
    gram(<List<double>>[
      for (int r = 0; r < column.length; r++)
        <double>[1, ...terms[r], column[r]],
    ]),
  );
  if (own == null) return null;
  final int last = terms.first.length + 1;
  if (own[last][last] * ss > gates.maxVarianceInflation) return null;
  final double ssx = squares(judged.x);
  final List<List<double>>? withHabit = invert(
    gram(<List<double>>[
      for (int r = 0; r < column.length; r++)
        <double>[1, judged.x[r], ...terms[r], column[r]],
    ]),
  );
  if (withHabit == null || withHabit[1][1] * ssx > gates.maxVarianceInflation) {
    return null;
  }
  return column;
}

/// [insights] with every finding that fails Benjamini-Hochberg at
/// [InsightGates.falseDiscoveryRate] refused as [RefusalReason.chance]. The
/// family is every result with a p-value, so a fitted habit refused for its
/// entanglement or its noise still counts as a comparison made. The
/// p-values in [alongside] are comparisons judged elsewhere that belong to
/// the same family.
List<HabitInsight> controlFalseDiscoveries(
  List<HabitInsight> insights, {
  InsightGates gates = const InsightGates(),
  List<double> alongside = const <double>[],
}) {
  final List<int> tested = <int>[
    for (int i = 0; i < insights.length; i++)
      if (insightPValue(insights[i]) != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) insightPValue(insights[i])!,
    ...alongside,
  ], gates.falseDiscoveryRate);
  final Set<int> rejected = <int>{
    for (int k = 0; k < tested.length; k++)
      if (!kept[k]) tested[k],
  };
  return <HabitInsight>[
    for (int i = 0; i < insights.length; i++)
      switch (insights[i]) {
        final HabitFinding f when rejected.contains(i) => HabitRefusal(
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
          reason: RefusalReason.chance,
          effect: f.effect,
          interval: f.interval,
          pValue: f.pValue,
        ),
        final HabitInsight other => other,
      },
  ];
}

// Which period each of [days] falls in, numbered from 0: one per calendar
// month, a month with fewer than [minDays] usable days merged into the next,
// and a short last one into the one before.
List<int> periodsOf(List<DateTime> days, int minDays) {
  final List<int> period = List<int>.filled(days.length, 0);
  int current = 0, inCurrent = 0, monthStart = 0;
  for (int r = 0; r <= days.length; r++) {
    final bool monthEnds =
        r == days.length ||
        (r > 0 &&
            (days[r].month != days[r - 1].month ||
                days[r].year != days[r - 1].year));
    if (monthEnds) {
      final int monthDays = r - monthStart;
      if (inCurrent >= minDays) {
        current++;
        inCurrent = 0;
      }
      for (int i = monthStart; i < r; i++) {
        period[i] = current;
      }
      inCurrent += monthDays;
      monthStart = r;
    }
  }
  if (inCurrent < minDays && current > 0) {
    for (int i = 0; i < days.length; i++) {
      if (period[i] == current) period[i] = current - 1;
    }
  }
  return period;
}

// Periods with days both with and without the habit, the only days its
// coefficient learns from once the period levels are in.
int _mixedPeriods(List<double> x, List<int> period) {
  final int periods = period.last + 1;
  final List<int> on = List<int>.filled(periods, 0);
  final List<int> all = List<int>.filled(periods, 0);
  for (int r = 0; r < x.length; r++) {
    all[period[r]]++;
    if (x[r] == 1) on[period[r]]++;
  }
  int mixed = 0;
  for (int k = 0; k < periods; k++) {
    if (on[k] > 0 && on[k] < all[k]) mixed++;
  }
  return mixed;
}

// The ratio alone would refuse a rare habit's chance clumping in a short
// span; the test alone would refuse a mild drift in a long one, which the time
// terms absorb. The ratio is checked on the days without the habit too: early
// days left unlogged by a daily habit read as days without it, the mirror of
// logging that fades. Days of use come in runs (a bad week, a trip), which
// makes the halves' rates differ more than independent days would, so the
// standard error is widened by the runs' lag-1 autocorrelation within each
// half.
bool unevenHalves(List<double> x, int half, InsightGates gates) {
  final List<double> a = x.sublist(0, half), b = x.sublist(half);
  final double ra = mean(a), rb = mean(b);
  bool lopsided(double p, double q) =>
      max(p, q) > gates.maxUseRateRatio * min(p, q);
  if (!lopsided(ra, rb) && !lopsided(1 - ra, 1 - rb)) return false;
  final double pooled =
      ((a.length - 1) * sampleVariance(a) +
          (b.length - 1) * sampleVariance(b)) /
      (x.length - 2);
  final double rho = _withinHalvesAutocorrelation(a, b);
  final double se = sqrt(
    pooled * (1 / a.length + 1 / b.length) * (1 + rho) / (1 - rho),
  );
  final double p = se == 0
      ? 0
      : studentTTwoSided((ra - rb) / se, (x.length - 2).toDouble());
  return p < gates.unevenSignificance;
}

// Clamped to [0, 0.9]: a negative value would narrow the interval, and one
// near 1 leaves no evidence at all.
double _withinHalvesAutocorrelation(List<double> a, List<double> b) {
  double lagged = 0, squares = 0;
  for (final List<double> part in <List<double>>[a, b]) {
    final double m = mean(part);
    for (int i = 0; i < part.length; i++) {
      squares += (part[i] - m) * (part[i] - m);
      if (i > 0) lagged += (part[i] - m) * (part[i - 1] - m);
    }
  }
  return squares == 0 ? 0 : (lagged / squares).clamp(0.0, 0.9);
}

Comparison? _welch(List<double> exposure, List<double> y, double level) {
  final List<double> on = <double>[], off = <double>[];
  for (int i = 0; i < y.length; i++) {
    (exposure[i] == 1 ? on : off).add(y[i]);
  }
  if (on.length < 2 || off.length < 2) return null;
  final double a = sampleVariance(on) / on.length;
  final double b = sampleVariance(off) / off.length;
  final double se = sqrt(a + b);
  final double df = a + b == 0
      ? (on.length + off.length - 2).toDouble()
      : (a + b) *
            (a + b) /
            (a * a / (on.length - 1) + b * b / (off.length - 1));
  final double difference = mean(on) - mean(off);
  final double half = studentTQuantile(1 - (1 - level) / 2, df) * se;
  return Comparison(
    exposedMean: mean(on),
    unexposedMean: mean(off),
    exposedDays: on.length,
    unexposedDays: off.length,
    interval: Interval(difference - half, difference + half),
  );
}
