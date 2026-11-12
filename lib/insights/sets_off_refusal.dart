import 'dart:math';

import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/insights/after_event.dart';
import 'package:tracker/insights/before_use.dart';
import 'package:tracker/insights/habit_follows.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/trigger_amounts.dart';
import 'package:tracker/insights/what_follows.dart';

/// Why a habit has nothing under "What sets it off": the most telling of its
/// refused before-a-use, pair, calendar and trigger comparisons, or, with
/// none of them, whether it has entries at all.
class SetsOffRefusal {
  const SetsOffRefusal.before(this.habitId, BeforeUse this.before)
    : pair = null,
      calendar = null,
      tagging = null,
      trigger = null,
      logged = true;
  const SetsOffRefusal.pair(this.habitId, HabitFollows this.pair)
    : before = null,
      calendar = null,
      tagging = null,
      trigger = null,
      logged = true;
  const SetsOffRefusal.calendar(this.habitId, AfterEvent this.calendar)
    : before = null,
      pair = null,
      tagging = null,
      trigger = null,
      logged = true;
  const SetsOffRefusal.trigger(
    this.habitId,
    HabitTriggers this.tagging,
    TriggerAmount this.trigger,
  ) : before = null,
      pair = null,
      calendar = null,
      logged = true;
  const SetsOffRefusal.nothing(this.habitId, {required this.logged})
    : before = null,
      pair = null,
      calendar = null,
      tagging = null,
      trigger = null;

  final String habitId;
  final BeforeUse? before;
  final HabitFollows? pair;
  final AfterEvent? calendar;

  /// With [trigger]: the habit's tagging as a whole.
  final HabitTriggers? tagging;
  final TriggerAmount? trigger;

  /// With no comparison: whether the habit has entries in the span read.
  final bool logged;

  RefusalReason? get reason =>
      before?.refusal ??
      calendar?.refusal ??
      switch (pair?.verdict) {
        FollowsVerdict.tooFewDays => RefusalReason.tooFewDays,
        FollowsVerdict.chance => RefusalReason.chance,
        FollowsVerdict.tooSmall => RefusalReason.tooSmall,
        _ => null,
      } ??
      switch (trigger?.verdict) {
        TriggerVerdict.tooFewDays => RefusalReason.tooFewDays,
        TriggerVerdict.steadyAmount => RefusalReason.steadyAmount,
        TriggerVerdict.chance => RefusalReason.chance,
        TriggerVerdict.tooSmall => RefusalReason.tooSmall,
        _ => null,
      };

  int get _days =>
      before?.usableDays ??
      pair?.days ??
      calendar?.eventDays ??
      trigger?.withDays ??
      0;

  int get _source => before != null
      ? 0
      : pair != null
      ? 1
      : calendar != null
      ? 2
      : 3;
}

/// One [SetsOffRefusal] for each of [habitIds] (the unarchived habits shown,
/// in order) that no card in [shown] names, from [report]'s before-a-use,
/// pair, calendar and trigger comparisons; [logged] holds the habits with entries in
/// the span read. Ranked as [refusalRank], then before-a-use, pair,
/// calendar and trigger, then the comparison from the most days.
List<SetsOffRefusal> setsOffRefusals({
  required Iterable<String> habitIds,
  required InsightsReport report,
  required Set<String> shown,
  required Set<String> logged,
}) {
  final Set<String> ids = habitIds.toSet();
  final Map<String, List<SetsOffRefusal>> byHabit =
      <String, List<SetsOffRefusal>>{};
  void add(SetsOffRefusal r) {
    if (r.reason == null || shown.contains(r.habitId)) return;
    byHabit.putIfAbsent(r.habitId, () => <SetsOffRefusal>[]).add(r);
  }

  for (final BeforeUse b in report.beforeUse) {
    if (metricCopy(b.metricId) != null) {
      add(SetsOffRefusal.before(b.habitId, b));
    }
  }
  for (final HabitFollows f in report.follows) {
    if (!ids.contains(f.leadId) || !ids.contains(f.followerId)) continue;
    add(SetsOffRefusal.pair(f.leadId, f));
    add(SetsOffRefusal.pair(f.followerId, f));
  }
  for (final AfterEvent a in report.afterEvent) {
    add(SetsOffRefusal.calendar(a.habitId, a));
  }
  for (final HabitTriggers h in report.triggers) {
    for (final TriggerAmount t in h.triggers) {
      add(SetsOffRefusal.trigger(h.habitId, h, t));
    }
  }
  return <SetsOffRefusal>[
    for (final String id in habitIds)
      if (!shown.contains(id))
        switch (byHabit[id]) {
          final List<SetsOffRefusal> all => all.reduce(_moreTelling),
          null => SetsOffRefusal.nothing(id, logged: logged.contains(id)),
        },
  ];
}

SetsOffRefusal _moreTelling(SetsOffRefusal a, SetsOffRefusal b) {
  final int byReason = refusalRank(a.reason!).compareTo(refusalRank(b.reason!));
  if (byReason != 0) return byReason < 0 ? a : b;
  final int bySource = a._source.compareTo(b._source);
  if (bySource != 0) return bySource < 0 ? a : b;
  return b._days > a._days ? b : a;
}

/// [refusal] in plain words, led by what was compared, as [refusalReason]
/// leads with an amount or a time.
String setsOffReason(
  SetsOffRefusal refusal,
  String Function(String habitId) nameOf, {
  InsightGates gates = const InsightGates(),
  Map<String, double> floors = const <String, double>{},
}) {
  if (refusal.before case final BeforeUse b) {
    return 'Before it: ${_beforeReason(b, gates, floors)}';
  }
  if (refusal.pair case final HabitFollows f) {
    final String other = nameOf(
      f.leadId == refusal.habitId ? f.followerId : f.leadId,
    );
    return 'With $other: ${_pairReason(f, gates)}';
  }
  if (refusal.calendar case final AfterEvent a) {
    return 'After calendar events: ${_calendarReason(a, gates)}';
  }
  if ((refusal.tagging, refusal.trigger) case (
    final HabitTriggers h,
    final TriggerAmount t,
  )) {
    return 'Tagged ${triggerDisplay(t.trigger)}: ${_triggerReason(h, t, gates)}';
  }
  return refusal.logged
      ? 'Nothing to compare it with yet: no sleep or heart readings in '
            'Health, no calendar events, no other habit logged and no '
            'triggers tagged'
      : 'No entries yet in the time Insights reads';
}

String _beforeReason(BeforeUse b, InsightGates gates, Map<String, double> f) =>
    switch (b.refusal!) {
      RefusalReason.tooFewDays => _beforeTooFew(b, gates),
      RefusalReason.tooSmall =>
        'too small to matter, ${underFloor(b.metricId, f)}',
      RefusalReason.chance => 'could be chance, one of many comparisons',
      RefusalReason.withinNoise => 'within the noise, no clear difference',
      RefusalReason.oneDay =>
        'rests on one unusual day, so it may not hold on the others',
      RefusalReason.uneven =>
        'used far more at some times than others, so it can’t be told apart '
            'from other changes',
      RefusalReason.entangled =>
        'used together with other habits, so they can’t be told apart',
      RefusalReason.steadyAmount || RefusalReason.steadyTiming =>
        'nearly the same each day, so there’s no difference to compare',
      RefusalReason.followsAmount =>
        'later on days with more, so it can’t be told apart from the amount',
      RefusalReason.followsBedtime =>
        'moves with when you fall asleep, so it can’t be told apart from '
            'your bedtime',
    };

// A count is said only where it is the gate that stopped the comparison.
String _beforeTooFew(BeforeUse b, InsightGates gates) {
  if (b.kind == BeforeUseKind.hourBefore) {
    return 'too few uses yet with a clear hour before them to compare';
  }
  if (b.usableDays < gates.minDays) {
    return 'too few days yet: ${b.usableDays} of ${gates.minDays}';
  }
  if (b.kind == BeforeUseKind.whether) {
    if (b.usableDays - b.exposedDays < gates.minUnexposedDays) {
      return 'used almost every day, too few days without it to compare';
    }
    if (b.exposedDays < gates.minExposedDays) {
      return 'too few days with it yet: ${b.exposedDays} of '
          '${gates.minExposedDays}';
    }
  }
  return 'too few days yet to compare';
}

String _pairReason(HabitFollows f, InsightGates gates) => switch (f.verdict!) {
  FollowsVerdict.tooFewDays when f.days < gates.minDays =>
    'too few days with both yet: ${f.days} of ${gates.minDays}',
  FollowsVerdict.tooFewDays =>
    'too few days with one soon after the other yet: ${f.followedDays} of '
        '${gates.minExposedDays}',
  FollowsVerdict.chance when f.excess <= 0 =>
    'no more often than your usual timing of each would give',
  FollowsVerdict.chance => 'could be chance, one of many comparisons',
  FollowsVerdict.tooSmall =>
    'too small to matter, under ${(followFloor * 100).round()} points over '
        'your usual timing',
  FollowsVerdict.found => '',
};

String _calendarReason(AfterEvent a, InsightGates gates) {
  final int least = max(afterEventMinDays, gates.minExposedDays);
  return switch (a.refusal!) {
    RefusalReason.tooFewDays when a.eventDays < least =>
      'too few days with events yet: ${a.eventDays} of $least',
    RefusalReason.tooFewDays when a.controlDays < least =>
      'too few nearby days clear of events to compare: ${a.controlDays} of '
          '$least',
    RefusalReason.tooFewDays => 'too few days yet to compare',
    RefusalReason.chance => 'could be chance, one of many comparisons',
    RefusalReason.tooSmall =>
      'too small to matter, under ${(afterEventFloor * 100).round()} points '
          'more or less often',
    _ => 'within the noise, no clear difference',
  };
}

// Only tagged entries are compared, so the count of them leads a shortfall.
String _triggerReason(HabitTriggers h, TriggerAmount t, InsightGates gates) =>
    switch (t.verdict!) {
      TriggerVerdict.tooFewDays when t.withDays < gates.minExposedDays =>
        'too few days with it yet: ${t.withDays} of ${gates.minExposedDays} '
            '(${h.tagged} of ${h.entries} entries tagged)',
      TriggerVerdict.tooFewDays =>
        'too few days tagged otherwise to compare: ${t.withoutDays} of '
            '${gates.minUnexposedDays} (${h.tagged} of ${h.entries} entries '
            'tagged)',
      TriggerVerdict.steadyAmount =>
        'the same amount on every tagged entry, so there’s no difference to '
            'compare',
      TriggerVerdict.chance => 'could be chance, one of many comparisons',
      TriggerVerdict.tooSmall =>
        'too small to matter, under ${(triggerFloor * 100).round()}% more or '
            'less than on your other tagged entries',
      TriggerVerdict.found => '',
    };
