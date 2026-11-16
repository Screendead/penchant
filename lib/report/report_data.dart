import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/habit_strength.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/usage_series.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/habit_mark.dart';

// What the person asks the report to cover. [months] counts calendar months
// back from the one holding today, so a three-month report is three whole
// calendar grids and fits one page per habit.
@immutable
class ReportOptions {
  const ReportOptions({
    required this.viceIDs,
    this.months = 3,
    this.includeNotes = false,
    this.firstWeekday = DateTime.monday,
  });

  final Set<String> viceIDs;
  final int months;
  // Notes, day notes and tags in the person's own words: the report's only
  // free text, so all three follow the one tick.
  final bool includeNotes;
  // DateTime.monday to DateTime.sunday: where calendar rows and weeks begin.
  final int firstWeekday;

  static const List<int> monthChoices = <int>[1, 3, 6, 12];

  ReportOptions copyWith({
    Set<String>? viceIDs,
    int? months,
    bool? includeNotes,
  }) => ReportOptions(
    viceIDs: viceIDs ?? this.viceIDs,
    months: months ?? this.months,
    includeNotes: includeNotes ?? this.includeNotes,
    firstWeekday: firstWeekday,
  );
}

// From the first of the earliest month to the midnight after [today].
typedef ReportWindow = ({DateTime start, DateTime end});

ReportWindow reportWindow(DateTime today, int months) => (
  start: DateTime(today.year, today.month - (months - 1)),
  end: addDays(startOfDay(today), 1),
);

typedef ReportWeek = ({
  // The first day of the week inside the window, and how many of its days
  // the window holds: the first and last weeks may be short.
  DateTime start,
  int days,
  double total,
  // In the habit's strength unit; null without a strength.
  double? units,
});

typedef ReportTag = ({String label, int entries});

typedef ReportNote = ({DateTime at, String text});

@immutable
class HabitReport {
  const HabitReport({
    required this.name,
    required this.units,
    required this.mark,
    required this.days,
    required this.weeks,
    required this.entries,
    required this.hours,
    required this.hourDays,
    required this.tags,
    required this.taggedEntries,
    required this.notes,
    this.strength,
    this.unitsWithout = 0,
  });

  final String name;
  final UnitWords units;
  final HabitMark mark;
  // Each day's total, from the window's first day.
  final List<double> days;
  final List<ReportWeek> weeks;
  final int entries;
  final HabitStrength? strength;
  // Entries the strength could not count (an alcohol habit without its ABV).
  final int unitsWithout;
  final HourProfile hours;
  // How many days, ending with the window, [hours] covers.
  final int hourDays;
  final List<ReportTag> tags;
  final int taggedEntries;
  final List<ReportNote> notes;

  double get total => days.fold<double>(0, (double a, double b) => a + b);

  int get daysWithEntries => days.where((double d) => d > 0).length;

  double? get unitsTotal => strength == null
      ? null
      : weeks.fold<double>(0, (double a, ReportWeek w) => a + (w.units ?? 0));
}

@immutable
class ReportData {
  const ReportData({
    required this.window,
    required this.made,
    required this.firstWeekday,
    required this.habits,
    required this.dayNotes,
    required this.notesIncluded,
    required this.lockedEntries,
    required this.lockedHabits,
  });

  final ReportWindow window;
  final DateTime made;
  final int firstWeekday;
  final List<HabitReport> habits;
  final List<ReportNote> dayNotes;
  final bool notesIncluded;
  final int lockedEntries;
  final int lockedHabits;

  int get dayCount => daysBetween(window.start, window.end);
}

const int reportTagCount = 6;

// Everything the PDF shows, from the journal the export reads. Notes, day
// notes and own-words tags are left out here unless ticked, and entries or
// habits that would not open are only counted, so the PDF builder never sees
// them.
ReportData buildReport(
  AccountData data,
  ReportOptions options, {
  required DateTime now,
}) {
  final ReportWindow window = reportWindow(now, options.months);
  // A document fetchData could not open still holds its envelope.
  Map<String, Object?>? opened(Map<String, dynamic> json) =>
      isSealed(json) ? null : json;

  final List<Vice> vices = <Vice>[
    for (final StoredDocument doc in data.vices)
      Vice.fromJson(id: doc.id, json: doc.data, opened: opened(doc.data)),
  ];
  final Map<String, HabitMark> marks = habitMarks(vices);
  final Map<String, Vice> chosen = <String, Vice>{
    for (final Vice vice in vices)
      if (options.viceIDs.contains(vice.id) && !vice.locked) vice.id: vice,
  };

  int lockedEntries = 0;
  final Map<String, List<ViceActivity>> byVice = <String, List<ViceActivity>>{};
  for (final StoredDocument doc in data.activities) {
    final ViceActivity activity = ViceActivity.fromJson(
      id: doc.id,
      json: doc.data,
      opened: opened(doc.data),
    );
    final DateTime at = activity.createdAt.toDate();
    if (!options.viceIDs.contains(activity.viceID) ||
        at.isBefore(window.start) ||
        !at.isBefore(window.end)) {
      continue;
    }
    if (activity.locked) {
      lockedEntries++;
      continue;
    }
    if (chosen.containsKey(activity.viceID)) {
      byVice.putIfAbsent(activity.viceID, () => <ViceActivity>[]).add(activity);
    }
  }

  final List<Vice> ordered = chosen.values.toList()
    ..sort(
      (Vice a, Vice b) => marks[a.id]!.creationIndex.compareTo(
        marks[b.id]!.creationIndex,
      ),
    );

  return ReportData(
    window: window,
    made: now,
    firstWeekday: options.firstWeekday,
    habits: <HabitReport>[
      for (final Vice vice in ordered)
        _habitReport(
          vice,
          marks[vice.id]!,
          byVice[vice.id] ?? const <ViceActivity>[],
          window,
          options,
        ),
    ],
    dayNotes: options.includeNotes ? _dayNotes(data, window) : const [],
    notesIncluded: options.includeNotes,
    lockedEntries: lockedEntries,
    lockedHabits: vices
        .where((Vice v) => v.locked && options.viceIDs.contains(v.id))
        .length,
  );
}

HabitReport _habitReport(
  Vice vice,
  HabitMark mark,
  List<ViceActivity> activities,
  ReportWindow window,
  ReportOptions options,
) {
  final UsageRange days = (
    start: window.start,
    days: daysBetween(window.start, window.end),
    stepDays: 1,
  );
  // Whole weeks from the one holding the window's first day; activities are
  // already inside the window, so the short end weeks hold only its days.
  final DateTime weekStart = addDays(
    window.start,
    -((window.start.weekday - options.firstWeekday) % 7),
  );
  final int weekDays = daysBetween(weekStart, window.end);
  final UsageRange weeks = (
    start: weekStart,
    days: (weekDays + 6) ~/ 7 * 7,
    stepDays: 7,
  );
  final List<double> weekTotals = bucketTotals(weeks, activities);
  final HabitStrength? strength = vice.strength;
  final UnitTotals? units = strength == null
      ? null
      : bucketUnits(weeks, activities, strength);

  final Map<String, int> tagCounts = <String, int>{};
  int tagged = 0;
  final List<ReportNote> notes = <ReportNote>[];
  for (final ViceActivity activity in activities) {
    final Iterable<String> tags = activity.triggers.toSet().where(
      (String t) => options.includeNotes || !isFreeTextTrigger(t),
    );
    if (tags.isNotEmpty) {
      tagged++;
    }
    for (final String tag in tags) {
      final String label = triggerDisplay(tag);
      tagCounts[label] = (tagCounts[label] ?? 0) + 1;
    }
    final String? note = activity.note;
    if (options.includeNotes && note != null && note.isNotEmpty) {
      notes.add((at: activity.createdAt.toDate(), text: note));
    }
  }
  final List<ReportTag> tags =
      <ReportTag>[
          for (final MapEntry<String, int>(:key, :value) in tagCounts.entries)
            (label: key, entries: value),
        ]
        ..sort((ReportTag a, ReportTag b) {
          final int byCount = b.entries.compareTo(a.entries);
          return byCount != 0 ? byCount : a.label.compareTo(b.label);
        });
  notes.sort((ReportNote a, ReportNote b) => a.at.compareTo(b.at));

  return HabitReport(
    name: vice.name,
    units: vice.units,
    mark: mark,
    days: bucketTotals(days, activities),
    weeks: <ReportWeek>[
      for (int i = 0; i < weeks.bucketCount; i++)
        _week(weeks.bucketStart(i), window, weekTotals[i], units?.totals[i]),
    ],
    entries: activities.length,
    strength: strength,
    unitsWithout: units?.without ?? 0,
    hours: hourProfile(days, activities),
    hourDays: min(days.days, hourProfileMaxDays),
    tags: tags.take(reportTagCount).toList(),
    taggedEntries: tagged,
    notes: notes,
  );
}

ReportWeek _week(
  DateTime start,
  ReportWindow window,
  double total,
  double? units,
) {
  final DateTime from = start.isBefore(window.start) ? window.start : start;
  final DateTime end = addDays(start, 7);
  final DateTime to = end.isAfter(window.end) ? window.end : end;
  return (
    start: from,
    days: daysBetween(from, to),
    total: total,
    units: units,
  );
}

List<ReportNote> _dayNotes(AccountData data, ReportWindow window) {
  final List<ReportNote> notes = <ReportNote>[];
  for (final StoredDocument doc in data.dayNotes) {
    final Object? day = doc.data['day'];
    final Object? text = doc.data[dayNoteTextField];
    final DateTime? at = day is String ? parseDayKey(day) : null;
    if (at == null ||
        text is! String ||
        text.trim().isEmpty ||
        at.isBefore(window.start) ||
        !at.isBefore(window.end)) {
      continue;
    }
    notes.add((at: at, text: text.trim()));
  }
  return notes..sort((ReportNote a, ReportNote b) => a.at.compareTo(b.at));
}
