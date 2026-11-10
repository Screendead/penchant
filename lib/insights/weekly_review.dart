import 'package:tracker/data/day.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/what_follows.dart';

typedef ReviewWeek = ({DateTime start, DateTime end});

/// The weeks before the reviewed one that "usual" averages over.
const int reviewPriorWeeks = 4;

/// The last whole Monday-to-Sunday week before [today], as [start, end).
ReviewWeek reviewWeek(DateTime today) {
  final DateTime day = startOfDay(today);
  final DateTime monday = addDays(day, DateTime.monday - day.weekday);
  return (start: addDays(monday, -7), end: monday);
}

/// The reviewed week and the [reviewPriorWeeks] before it.
({DateTime start, DateTime end}) reviewRange(ReviewWeek week) =>
    (start: addDays(week.start, -7 * reviewPriorWeeks), end: week.end);

/// One habit's week: [total] over the reviewed week, [weeks] the totals of
/// the weeks before it and then the reviewed week, oldest first, and [usual]
/// the mean of the earlier weeks the habit existed for; null when it existed
/// for none of them.
typedef HabitWeek = ({
  Vice vice,
  num total,
  int entries,
  List<num> weeks,
  double? usual,
});

typedef HourCount = ({int hour, int entries});

typedef TriggerCount = ({String label, int entries});

class WeeklyReview {
  const WeeklyReview({
    required this.week,
    required this.habits,
    required this.hours,
    required this.triggers,
  });

  final ReviewWeek week;

  /// Every unarchived habit, and an archived one only with entries in the
  /// week, in [vices]' order.
  final List<HabitWeek> habits;

  /// The week's entries by local hour, 0 to 23.
  final List<int> hours;

  /// Most entries first; ties by label.
  final List<TriggerCount> triggers;

  int get entries => hours.fold(0, (int a, int b) => a + b);

  /// The [n] hours with most entries, most first, earlier first on a tie.
  List<HourCount> busiest(int n) {
    final List<HourCount> all =
        <HourCount>[
          for (int h = 0; h < 24; h++)
            if (hours[h] > 0) (hour: h, entries: hours[h]),
        ]..sort((a, b) {
          final int byCount = b.entries.compareTo(a.entries);
          return byCount != 0 ? byCount : a.hour.compareTo(b.hour);
        });
    return all.take(n).toList();
  }
}

/// The review of [week] from [activities] (at least [reviewRange]'s), with
/// habits in [vices]' order.
WeeklyReview buildWeeklyReview({
  required ReviewWeek week,
  required List<Vice> vices,
  required Iterable<ViceActivity> activities,
}) {
  final List<DateTime> starts = <DateTime>[
    for (int i = reviewPriorWeeks; i >= 0; i--) addDays(week.start, -7 * i),
  ];
  final Map<String, List<num>> totals = <String, List<num>>{};
  final Map<String, int> entries = <String, int>{};
  final List<int> hours = List<int>.filled(24, 0);
  final Map<String, int> triggers = <String, int>{};
  for (final ViceActivity a in activities) {
    final DateTime at = a.createdAt.toDate();
    if (at.isBefore(starts.first) || !at.isBefore(week.end)) continue;
    int index = starts.length - 1;
    while (at.isBefore(starts[index])) {
      index--;
    }
    (totals[a.viceID] ??= List<num>.filled(starts.length, 0))[index] +=
        a.measure;
    if (index != starts.length - 1) continue;
    entries[a.viceID] = (entries[a.viceID] ?? 0) + 1;
    hours[at.hour]++;
    for (final String path in a.triggers) {
      final String label = triggerDisplay(path).trim();
      if (label.isEmpty) continue;
      triggers[label] = (triggers[label] ?? 0) + 1;
    }
  }
  final List<HabitWeek> habits = <HabitWeek>[
    for (final Vice v in vices)
      if (!v.archived || (entries[v.id] ?? 0) > 0)
        _habitWeek(v, totals[v.id], entries[v.id] ?? 0, starts),
  ];
  return WeeklyReview(
    week: week,
    habits: habits,
    hours: hours,
    triggers:
        <TriggerCount>[
          for (final MapEntry<String, int> e in triggers.entries)
            (label: e.key, entries: e.value),
        ]..sort((a, b) {
          final int byCount = b.entries.compareTo(a.entries);
          return byCount != 0 ? byCount : a.label.compareTo(b.label);
        }),
  );
}

HabitWeek _habitWeek(
  Vice vice,
  List<num>? totals,
  int entries,
  List<DateTime> starts,
) {
  final List<num> weeks = totals ?? List<num>.filled(starts.length, 0);
  final DateTime created = startOfDay(vice.createdAt.toDate());
  num sum = 0;
  int counted = 0;
  for (int i = 0; i < starts.length - 1; i++) {
    // A week the habit existed for any part of; one with entries counts
    // whatever its createdAt says.
    if (weeks[i] > 0 || created.isBefore(starts[i + 1])) {
      sum += weeks[i];
      counted++;
    }
  }
  return (
    vice: vice,
    total: weeks.last,
    entries: entries,
    weeks: weeks,
    usual: counted == 0 ? null : sum / counted,
  );
}

typedef CardKey = (String habitId, MetricFamily family);

/// What changed between the report as the week before ended ([before]) and
/// as the reviewed week ended ([after]): cards that newly stand out, cards
/// that no longer do (as [before] worded them), and those still holding.
typedef InsightChanges = ({
  List<InsightCard> started,
  List<InsightCard> stopped,
  List<InsightCard> holding,
});

InsightChanges insightChanges(InsightsReport before, InsightsReport after) {
  final List<InsightCard> was = insightCards(
    before.findings,
    floors: before.floors,
  );
  final List<InsightCard> now = insightCards(
    after.findings,
    floors: after.floors,
  );
  CardKey key(InsightCard c) => (c.habitId, c.family);
  final Set<CardKey> wasKeys = <CardKey>{for (final c in was) key(c)};
  final Set<CardKey> nowKeys = <CardKey>{for (final c in now) key(c)};
  return (
    started: <InsightCard>[
      for (final c in now)
        if (!wasKeys.contains(key(c))) c,
    ],
    stopped: <InsightCard>[
      for (final c in was)
        if (!nowKeys.contains(key(c))) c,
    ],
    holding: <InsightCard>[
      for (final c in now)
        if (wasKeys.contains(key(c))) c,
    ],
  );
}

/// The habits the engine has too few days for yet, from [report]'s refusals.
List<HabitRefusal> stillCollecting(InsightsReport report) => <HabitRefusal>[
  for (final HabitRefusal r in report.refused)
    if (r.reason == RefusalReason.tooFewDays) r,
];
