import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/payoff.dart';
import 'package:tracker/insights/stats.dart';

/// The fewest days with an entry a habit needs since another's fall before
/// its rise is tested.
const int minRiserDays = 7;

/// How far back the same weeks of the year before are looked at: 52 weeks,
/// so each day keeps its weekday.
const int yearBackDays = 364;

enum ReplacementRefusal {
  /// Under [minRiserDays] days with an entry since the fall, or too few days
  /// for the model.
  tooFewDays,

  /// Another habit fell within [PayoffGates.sameFallDays] of the fall, so a
  /// rise goes with neither alone. Nothing is fitted.
  otherFall,

  /// The interval for the change includes zero, or the change is a fall.
  noRise,

  /// The same model finds a change halfway through the baseline, before the
  /// other habit had moved.
  alreadyMoving,

  /// Higher since the fall, but the habit's own entries place no rise of
  /// [PayoffGates.minFall], kept to the latest days, within
  /// [PayoffGates.sameFallDays] of it.
  notThen,

  /// The same model finds a rise over the same weeks [yearBackDays] earlier:
  /// the time of year may be moving both.
  sameLastYear,

  /// Does not stand out among every comparison in the report. Set by
  /// [judgeReplacements].
  chance,
}

/// One habit's daily amount since another's fall against its level before: a
/// finding when [refusal] is null.
class Replacement {
  const Replacement({
    required this.fall,
    required this.riserId,
    required this.before,
    required this.since,
    required this.baselineDays,
    required this.sinceDays,
    this.effect,
    this.interval,
    this.pValue,
    this.refusal,
    this.began = false,
  });

  /// The habit that fell, and when.
  final HabitFall fall;
  final String riserId;

  /// [riserId]'s mean a day over the fall's baseline, and from the fall to
  /// [PayoffGates.sinceDays] after it.
  final double before;
  final double since;

  /// The days behind [before] and [since].
  final int baselineDays;
  final int sinceDays;

  /// The step in [riserId]'s daily amount at the fall, with the trend, the
  /// weekend and day-to-day carry-over allowed for.
  final double? effect;
  final Interval? interval;

  /// Set once fitted: the comparison then counts in the report's family.
  final double? pValue;
  final ReplacementRefusal? refusal;

  String get habitId => fall.habitId;
  bool get found => refusal == null;

  /// No entry at all before the fall: the journal cannot tell a habit taken
  /// up from one newly logged.
  final bool began;

  /// Entries before the baseline, none in it.
  bool get resumed => before == 0 && !began;

  Replacement refused(ReplacementRefusal reason) => Replacement(
    fall: fall,
    riserId: riserId,
    before: before,
    since: since,
    baselineDays: baselineDays,
    sinceDays: sinceDays,
    effect: effect,
    interval: interval,
    pValue: pValue,
    refusal: reason,
    began: began,
  );
}

/// For each habit that [findFalls] gives a fall, every other habit's daily
/// amount since that fall against before it, neither habit in [skip]. No
/// measure is read: the journal alone.
///
/// The fall's day comes from the fallen habit's entries only, so the test on
/// the other habit at that day is an honest one: [measureSince]'s model on
/// its daily totals, a day with no entry counting as zero (a level, a step
/// at the fall, a straight trend, the weekend, errors carrying over from day
/// to day). The trend and weekend terms, the placebo step
/// ([ReplacementRefusal.alreadyMoving]) and the year-before check
/// ([ReplacementRefusal.sameLastYear], when the journal reaches that far)
/// are what keep two habits that each follow the calendar from reading as
/// one rising for the other.
///
/// A step over 13 weeks would also show for a rise that came six weeks
/// later, so the riser's own entries must place a rise ([bestShift]) within
/// [PayoffGates.sameFallDays] of the fall. That gate gives no p-value; it
/// only refuses. It is also the size floor: at least [PayoffGates.minFall]
/// over the riser's baseline, kept over the latest days.
List<Replacement> replacement({
  required List<HabitUse> uses,
  required DateTime through,
  Set<String> skip = const <String>{},
  PayoffGates gates = const PayoffGates(),
}) {
  final DateTime last = startOfDay(through);
  final DailyHabitSeries habits = DailyHabitSeries.fromUses(uses);
  final DateTime? journalStart = habits.firstDay;
  if (journalStart == null) return const <Replacement>[];
  final Map<String, HabitFall> falls = findFalls(habits, last, gates: gates);
  final List<String> ids = <String>[
    for (final String id in habits.habitIds)
      if (habits.firstUse(id) != null) id,
  ]..sort();
  final List<DateTime> journal = daysFrom(journalStart, last).toList();
  final List<Replacement> out = <Replacement>[];
  for (final String fallen in falls.keys.toList()..sort()) {
    if (skip.contains(fallen)) continue;
    final HabitFall fall = falls[fallen]!;
    final bool shared = falls.values.any(
      (HabitFall other) =>
          other.habitId != fallen &&
          daysBetween(fall.day, other.day).abs() <= gates.sameFallDays,
    );
    final DateTime capped = addDays(fall.day, gates.sinceDays);
    final DateTime windowEnd = capped.isAfter(last) ? last : capped;
    for (final String riser in ids) {
      if (riser == fallen || skip.contains(riser)) continue;
      final List<double> baseline = <double>[
        for (final DateTime day in daysFrom(fall.from, addDays(fall.day, -1)))
          habits.total(riser, day),
      ];
      final List<double> after = <double>[
        for (final DateTime day in daysFrom(fall.day, windowEnd))
          habits.total(riser, day),
      ];
      Replacement result({ReplacementRefusal? refusal, Payoff? fitted}) =>
          Replacement(
            fall: fall,
            riserId: riser,
            before: mean(baseline),
            since: mean(after),
            baselineDays: baseline.length,
            sinceDays: after.length,
            effect: fitted?.effect,
            interval: fitted?.interval,
            pValue: fitted?.pValue,
            refusal: refusal,
            began: !habits.firstUse(riser)!.isBefore(fall.day),
          );
      if (shared) {
        out.add(result(refusal: ReplacementRefusal.otherFall));
        continue;
      }
      if (after.where((double v) => v > 0).length < minRiserDays) {
        out.add(result(refusal: ReplacementRefusal.tooFewDays));
        continue;
      }
      final List<double> totals = <double>[
        for (final DateTime day in journal) habits.total(riser, day),
      ];
      final OutcomeSeries series = OutcomeSeries.fromOutcomes(<DailyOutcome>[
        for (int i = 0; i < journal.length; i++)
          DailyOutcome(date: journal[i], metricId: riser, value: totals[i]),
      ]);
      final Payoff fitted = measureSince(fall, riser, series, last, gates);
      if (fitted.pValue == null) {
        out.add(result(refusal: ReplacementRefusal.tooFewDays));
        continue;
      }
      out.add(
        result(
          fitted: fitted,
          refusal: _refusal(fall, fitted, totals, journal, series, gates),
        ),
      );
    }
  }
  return out;
}

ReplacementRefusal? _refusal(
  HabitFall fall,
  Payoff fitted,
  List<double> totals,
  List<DateTime> journal,
  OutcomeSeries series,
  PayoffGates gates,
) {
  if (fitted.refusal == PayoffRefusal.withinNoise || fitted.effect! <= 0) {
    return ReplacementRefusal.noRise;
  }
  if (fitted.refusal != null) return ReplacementRefusal.alreadyMoving;
  final ShiftSplit? rise = bestShift(totals, gates, rising: true);
  if (rise == null ||
      daysBetween(fall.day, journal[rise.at]).abs() > gates.sameFallDays) {
    return ReplacementRefusal.notThen;
  }
  final DateTime yearBackFrom = addDays(fall.from, -yearBackDays);
  if (!journal.first.isAfter(yearBackFrom)) {
    final DateTime day = addDays(fall.day, -yearBackDays);
    final Payoff yearBack = measureSince(
      HabitFall(
        habitId: fall.habitId,
        day: day,
        from: yearBackFrom,
        before: fall.before,
        since: fall.since,
        sinceDays: fall.sinceDays,
      ),
      fitted.metricId,
      series,
      addDays(day, fitted.sinceValues),
      gates,
    );
    if (yearBack.found && yearBack.effect! > 0) {
      return ReplacementRefusal.sameLastYear;
    }
  }
  return null;
}

/// [results] judged as part of one family with the comparisons whose
/// p-values are [alongside]: a finding that fails Benjamini-Hochberg at
/// [PayoffGates.falseDiscoveryRate] over them all is refused as
/// [ReplacementRefusal.chance].
List<Replacement> judgeReplacements(
  List<Replacement> results, {
  List<double> alongside = const <double>[],
  PayoffGates gates = const PayoffGates(),
}) {
  final List<int> tested = <int>[
    for (int i = 0; i < results.length; i++)
      if (results[i].pValue != null) i,
  ];
  final List<bool> kept = benjaminiHochberg(<double>[
    for (final int i in tested) results[i].pValue!,
    ...alongside,
  ], gates.falseDiscoveryRate);
  final Set<int> chance = <int>{
    for (int k = 0; k < tested.length; k++)
      if (!kept[k]) tested[k],
  };
  return <Replacement>[
    for (int i = 0; i < results.length; i++)
      results[i].found && chance.contains(i)
          ? results[i].refused(ReplacementRefusal.chance)
          : results[i],
  ];
}

/// One habit's fall and the habits that rose with it, the clearest first.
class ReplacementCard {
  const ReplacementCard(this.fall, this.risers);

  final HabitFall fall;
  final List<Replacement> risers;

  String get habitId => fall.habitId;
}

/// The findings of [results] as one card per fallen habit, by the smallest
/// p-value, then by habit.
List<ReplacementCard> replacementCards(List<Replacement> results) {
  int clearest(Replacement a, Replacement b) {
    final int byP = a.pValue!.compareTo(b.pValue!);
    return byP != 0 ? byP : a.riserId.compareTo(b.riserId);
  }

  final Map<String, List<Replacement>> byFall = <String, List<Replacement>>{};
  for (final Replacement r in results) {
    if (r.found) byFall.putIfAbsent(r.habitId, () => <Replacement>[]).add(r);
  }
  final List<ReplacementCard> cards = <ReplacementCard>[
    for (final List<Replacement> risers in byFall.values)
      ReplacementCard(risers.first.fall, risers..sort(clearest)),
  ];
  return cards..sort((ReplacementCard a, ReplacementCard b) {
    final int byP = a.risers.first.pValue!.compareTo(b.risers.first.pValue!);
    return byP != 0 ? byP : a.habitId.compareTo(b.habitId);
  });
}
