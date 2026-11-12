import 'package:tracker/data/day.dart';
import 'package:tracker/insights/daily_series.dart';

/// [DayCondition.id] of the menstrual cycle's phase, and what a finding's
/// `heldFixed` names when its comparison held it.
const String cyclePhaseId = 'cyclePhase';

/// A [DayCondition.level] of [cyclePhaseId].
enum CyclePhase { menstrual, follicular, luteal }

/// FIGO's normal range for the days from one period's first day to the next's
/// (Munro 2018). A cycle outside it, from a missed or stray log as likely as
/// from the body, has no phases.
const int minCycleDays = 24;
const int maxCycleDays = 38;

/// The luteal phase, counted back from the next period's first day: its
/// length varies far less than the follicular phase's (Schmalenberger 2021,
/// 13.3 days on average, SD 2.1).
const int lutealDays = 14;

/// Days without flow before a flow day that make it a period's first day.
const int periodGapDays = 7;

/// The phase of each day inside a whole cycle of normal length, from the days
/// with flow ([flowDays]) alone: menstrual from a period's first day through
/// its last day of flow (a gap of one day without flow inside it allowed),
/// luteal for the [lutealDays] before the next period's first day, follicular
/// between. A day outside such a cycle (before the first period, in the cycle
/// still open, in one too short or too long) has no phase.
DayCondition cyclePhases(Iterable<DateTime> flowDays) {
  final Set<DateTime> flow = <DateTime>{
    for (final DateTime d in flowDays) startOfDay(d),
  };
  final List<DateTime> sorted = flow.toList()..sort();
  final List<DateTime> starts = <DateTime>[
    for (int i = 0; i < sorted.length; i++)
      if (i == 0 || daysBetween(sorted[i - 1], sorted[i]) > periodGapDays)
        sorted[i],
  ];
  final Map<DateTime, int> level = <DateTime, int>{};
  for (int k = 0; k + 1 < starts.length; k++) {
    final DateTime start = starts[k], next = starts[k + 1];
    final int length = daysBetween(start, next);
    if (length < minCycleDays || length > maxCycleDays) continue;
    final int luteal = length - lutealDays;
    int bleedEnd = 0;
    for (int day = 1; day < luteal && day - bleedEnd <= 2; day++) {
      if (flow.contains(addDays(start, day))) bleedEnd = day;
    }
    for (int day = 0; day < length; day++) {
      level[addDays(start, day)] =
          (day >= luteal
                  ? CyclePhase.luteal
                  : day <= bleedEnd
                  ? CyclePhase.menstrual
                  : CyclePhase.follicular)
              .index;
    }
  }
  return DayCondition(
    id: cyclePhaseId,
    levels: CyclePhase.values.length,
    level: level,
  );
}
