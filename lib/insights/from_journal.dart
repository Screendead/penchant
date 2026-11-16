import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart';
import 'package:tracker/insights/day_tags.dart';

/// The journal's entries as habit uses: each at its local time, by the amount
/// charts and totals count.
Iterable<HabitUse> habitUsesFrom(Iterable<ViceActivity> activities) =>
    activities.map(
      (a) => HabitUse(
        habitId: a.viceID,
        at: a.createdAt.toDate(),
        amount: a.measure,
        triggers: a.triggers,
        urge: a.urge,
        caughtUp: a.loggedVia == LoggedVia.caughtUp,
      ),
    );

/// Each day note holding a tag, as its day and tags; a locked note reads as
/// untagged, and one whose day is malformed is left out.
List<DayTags> dayTagsFrom(Iterable<DayNote> notes) => <DayTags>[
  for (final DayNote n in notes)
    if (!n.locked && n.triggers.isNotEmpty)
      if (parseDayKey(n.day) case final DateTime day)
        (day: day, triggers: n.triggers),
];
