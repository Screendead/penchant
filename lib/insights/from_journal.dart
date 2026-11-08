import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart';

/// The journal's entries as habit uses: each at its local time, by the amount
/// charts and totals count.
Iterable<HabitUse> habitUsesFrom(Iterable<ViceActivity> activities) =>
    activities.map(
      (a) => HabitUse(
        habitId: a.viceID,
        at: a.createdAt.toDate(),
        amount: a.measure,
      ),
    );
