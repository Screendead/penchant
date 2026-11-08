import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/habit_mark.dart';

// The days the snapshot carries, oldest first and ending today, and the window
// that ranks the top habits (r10-widget-top: most logged in 30 days).
const int widgetWeekDays = 7;
const int widgetTopWindowDays = 30;
const int widgetTopCount = 8;

// Read by ios/PenchantWidgets/Snapshot.swift; a change here is a change there.
const int widgetSnapshotVersion = 1;

String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

// What the widgets show, as JSON for the App Group. [vices] is every vice,
// archived ones included, so the colours match the app's; [activities] covers
// at least the [widgetTopWindowDays] days ending [today]. Locked vices are
// left out: their name is a placeholder, not the habit's.
Map<String, Object?> widgetSnapshot({
  required List<Vice> vices,
  required List<ViceActivity> activities,
  required DateTime today,
}) {
  final DateTime end = addDays(startOfDay(today), 1);
  final DateTime weekStart = addDays(end, -widgetWeekDays);
  final DateTime topStart = addDays(end, -widgetTopWindowDays);
  final List<String> days = <String>[
    for (int i = 0; i < widgetWeekDays; i++) dayKey(addDays(weekStart, i)),
  ];

  final Map<String, HabitMark> marks = habitMarks(vices);
  final List<Vice> shown =
      vices.where((Vice v) => !v.archived && !v.locked).toList()..sort(
        (Vice a, Vice b) =>
            marks[a.id]!.creationIndex.compareTo(marks[b.id]!.creationIndex),
      );
  final Set<String> shownIDs = <String>{for (final Vice v in shown) v.id};

  final Map<String, List<num>> week = <String, List<num>>{
    for (final Vice v in shown) v.id: List<num>.filled(widgetWeekDays, 0),
  };
  final Map<String, int> entries30 = <String, int>{
    for (final Vice v in shown) v.id: 0,
  };
  for (final ViceActivity a in activities) {
    if (!shownIDs.contains(a.viceID)) {
      continue;
    }
    final DateTime at = a.createdAt.toDate();
    if (at.isBefore(topStart) || !at.isBefore(end)) {
      continue;
    }
    entries30[a.viceID] = entries30[a.viceID]! + 1;
    if (!at.isBefore(weekStart)) {
      final int index = daysBetween(weekStart, at);
      week[a.viceID]![index] += a.measure;
    }
  }

  final List<Vice> ranked = <Vice>[...shown]
    ..sort((Vice a, Vice b) {
      final int byCount = entries30[b.id]!.compareTo(entries30[a.id]!);
      return byCount != 0
          ? byCount
          : marks[a.id]!.creationIndex.compareTo(marks[b.id]!.creationIndex);
    });

  return <String, Object?>{
    'version': widgetSnapshotVersion,
    'days': days,
    'habits': <Map<String, Object?>>[
      for (final Vice v in shown)
        <String, Object?>{
          'id': v.id,
          'name': v.name,
          'unitOne': v.unit.singular,
          'unitOther': v.unit.plural,
          'slot': marks[v.id]!.slot,
          'style': marks[v.id]!.style.name,
          'week': week[v.id],
          'entries30': entries30[v.id],
        },
    ],
    'top': <String>[for (final Vice v in ranked.take(widgetTopCount)) v.id],
  };
}
