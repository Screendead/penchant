import 'package:flutter/material.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';

/// The days before a day whose totals set what heavy means for it.
const int heavyWindowDays = 90;

/// How old a habit's first entry must be before any of its days is heavy.
const int heavyMinAgeDays = 30;

/// How many of the window's days must have use.
const int heavyMinUseDays = 10;

/// When the prompt about a heavy day first seen after the set time comes.
const TimeOfDay heavyMorningTime = TimeOfDay(hour: 9, minute: 0);

/// One habit's total of `measure` per local day.
Map<DateTime, num> dailyTotals(Iterable<ViceActivity> entries) {
  final Map<DateTime, num> totals = <DateTime, num>{};
  for (final ViceActivity a in entries) {
    final DateTime day = startOfDay(a.createdAt.toDate());
    totals[day] = (totals[day] ?? 0) + a.measure;
  }
  return totals;
}

/// Whether [day] is heavy for a habit with these [totals] (keyed by local
/// day) whose first entry was on [firstEntry]: its total is above the
/// nearest-rank 90th percentile of the totals of the [heavyWindowDays] days
/// before it that had any use.
bool isHeavyDay({
  required DateTime day,
  required Map<DateTime, num> totals,
  required DateTime? firstEntry,
}) {
  final DateTime start = startOfDay(day);
  if (firstEntry == null || daysBetween(firstEntry, start) < heavyMinAgeDays) {
    return false;
  }
  final num today = totals[start] ?? 0;
  if (today <= 0) return false;
  final DateTime windowStart = addDays(start, -heavyWindowDays);
  final List<num> used = <num>[
    for (final MapEntry<DateTime, num> e in totals.entries)
      if (!e.key.isBefore(windowStart) && e.key.isBefore(start) && e.value > 0)
        e.value,
  ]..sort();
  if (used.length < heavyMinUseDays) return false;
  // Nearest rank: the ceil(0.9 n)th smallest, in whole numbers.
  final int rank = (9 * used.length + 9) ~/ 10;
  return today > used[rank - 1];
}

/// Whether [day] is heavy for any of [habits], from [entries] covering at
/// least the [heavyWindowDays] days before it and the day itself. A habit's
/// first entry is the earliest in [entries], so one idle for longer than the
/// window counts as new again.
bool heavyDayOf({
  required DateTime day,
  required Iterable<Vice> habits,
  required Iterable<ViceActivity> entries,
}) {
  final DateTime end = addDays(startOfDay(day), 1);
  final Map<String, List<ViceActivity>> byHabit =
      <String, List<ViceActivity>>{};
  for (final ViceActivity a in entries) {
    if (!a.createdAt.toDate().isBefore(end)) continue;
    byHabit.putIfAbsent(a.viceID, () => <ViceActivity>[]).add(a);
  }
  for (final Vice habit in habits) {
    final List<ViceActivity>? own = byHabit[habit.id];
    if (own == null) continue;
    final Map<DateTime, num> totals = dailyTotals(own);
    final DateTime first = totals.keys.reduce(
      (DateTime a, DateTime b) => a.isBefore(b) ? a : b,
    );
    if (isHeavyDay(day: day, totals: totals, firstEntry: first)) return true;
  }
  return false;
}

/// One notification asking about the local day [about], due at [at].
@immutable
class HeavyPrompt {
  const HeavyPrompt(this.about, this.at);

  final DateTime about;
  final DateTime at;

  bool get aboutToday => startOfDay(at) == about;

  String encode() => '${localDateString(about)}|${at.toIso8601String()}';

  static HeavyPrompt? decode(String s) {
    final List<String> parts = s.split('|');
    if (parts.length != 2) return null;
    final DateTime? about = DateTime.tryParse(parts[0]);
    final DateTime? at = DateTime.tryParse(parts[1]);
    if (about == null || at == null) return null;
    return HeavyPrompt(startOfDay(about), at);
  }

  @override
  bool operator ==(Object other) =>
      other is HeavyPrompt && other.about == about && other.at == at;

  @override
  int get hashCode => Object.hash(about, at);

  @override
  String toString() => 'HeavyPrompt(${encode()})';
}

String localDateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _at(DateTime day, TimeOfDay time) =>
    DateTime(day.year, day.month, day.day, time.hour, time.minute);

/// The one prompt that should be pending at [now], or none. [fired] are the
/// prompts already delivered. At most one fires on a calendar day, and a day
/// is asked about at most once: the evening one at [time] while it is ahead,
/// else the next morning at [heavyMorningTime]. Of two candidates the earlier
/// wins; a day it crowds out is asked about the morning after.
HeavyPrompt? plannedHeavyPrompt({
  required DateTime now,
  required TimeOfDay time,
  required bool todayHeavy,
  required bool yesterdayHeavy,
  required Iterable<HeavyPrompt> fired,
}) {
  final DateTime today = startOfDay(now);
  final DateTime yesterday = addDays(today, -1);
  bool asked(DateTime day) => fired.any((HeavyPrompt p) => p.about == day);
  bool firesOn(DateTime day) =>
      fired.any((HeavyPrompt p) => startOfDay(p.at) == day);

  final List<HeavyPrompt> candidates = <HeavyPrompt>[
    if (todayHeavy && !asked(today))
      _at(today, time).isAfter(now)
          ? HeavyPrompt(today, _at(today, time))
          : HeavyPrompt(today, _at(addDays(today, 1), heavyMorningTime)),
    if (yesterdayHeavy &&
        !asked(yesterday) &&
        _at(today, heavyMorningTime).isAfter(now))
      HeavyPrompt(yesterday, _at(today, heavyMorningTime)),
  ]..removeWhere((HeavyPrompt p) => firesOn(startOfDay(p.at)));
  if (candidates.isEmpty) return null;
  return candidates.reduce(
    (HeavyPrompt a, HeavyPrompt b) => b.at.isBefore(a.at) ? b : a,
  );
}
