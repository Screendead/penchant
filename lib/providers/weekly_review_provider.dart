import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

/// The journal side of the review: needs no Health, so it shows everywhere.
final weeklyReviewProvider = Provider.autoDispose<AsyncValue<WeeklyReview>>((
  ref,
) {
  final ReviewWeek week = reviewWeek(ref.watch(todayProvider));
  final AsyncValue<List<ViceActivity>> activities = ref.watch(
    viceActivityRangeProvider(reviewRange(week)),
  );
  final AsyncValue<List<Vice>> vices = ref.watch(viceListProvider);
  if (activities case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<WeeklyReview>(error, stackTrace);
  }
  if (vices case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<WeeklyReview>(error, stackTrace);
  }
  final List<ViceActivity>? journal = activities.value;
  final List<Vice>? habits = vices.value;
  if (journal == null || habits == null) {
    return const AsyncLoading<WeeklyReview>();
  }
  return AsyncData<WeeklyReview>(
    buildWeeklyReview(week: week, vices: habits, activities: journal),
  );
});

sealed class WeeklyInsights {
  const WeeklyInsights();
}

/// No Health values to compare against; [health] says why.
final class WeeklyInsightsUnavailable extends WeeklyInsights {
  const WeeklyInsightsUnavailable(this.health);

  final HealthState health;
}

final class WeeklyInsightsFailed extends WeeklyInsights {
  const WeeklyInsightsFailed();
}

final class WeeklyInsightsComputed extends WeeklyInsights {
  const WeeklyInsightsComputed({
    required this.changes,
    required this.collecting,
    required this.floors,
  });

  final InsightChanges changes;
  final List<HabitRefusal> collecting;
  final Map<String, double> floors;
}

// A Firestore document ID never holds a '/', so it parts the IDs.
const String _archivedSeparator = '/';

typedef _WeeklyEngineKey = ({
  List<ViceActivity> activities,
  List<DailyOutcome> health,
  DateTime end,
  String archived,
});

// Health values stay on the device (insights_provider.dart): a failure is
// returned as a value, never thrown.
final _weeklyEngineProvider = FutureProvider.autoDispose
    .family<WeeklyInsights, _WeeklyEngineKey>((ref, key) async {
      final InsightsRunner run = ref.read(insightsRunnerProvider);
      final Set<String> archived = <String>{
        if (key.archived.isNotEmpty) ...key.archived.split(_archivedSeparator),
      };
      // Without the hours-after samples on either side, so the two reports
      // make the same comparisons.
      Future<InsightsReport> asOf(DateTime end) => run(
        InsightsInput.from(
          activities: <ViceActivity>[
            for (final ViceActivity a in key.activities)
              if (a.createdAt.toDate().isBefore(end)) a,
          ],
          health: <DailyOutcome>[
            for (final DailyOutcome o in key.health)
              if (!o.date.isAfter(end)) o,
          ],
          today: end,
          archived: archived,
        ),
      );
      try {
        final List<InsightsReport> reports = await Future.wait(
          <Future<InsightsReport>>[asOf(addDays(key.end, -7)), asOf(key.end)],
        );
        return WeeklyInsightsComputed(
          changes: insightChanges(reports[0], reports[1]),
          collecting: stillCollecting(reports[1]),
          floors: reports[1].floors,
        );
      } catch (_) {
        return const WeeklyInsightsFailed();
      }
    });

/// What the engine found by the end of the reviewed week against the end of
/// the week before. Reads the whole journal only when Health has values, as
/// Insights does, through the same query.
final weeklyInsightsProvider = Provider.autoDispose<AsyncValue<WeeklyInsights>>(
  (ref) {
    final HealthState? state = ref.watch(healthStateProvider).value;
    if (state == null) return const AsyncLoading<WeeklyInsights>();
    if (state case HealthReady(
      :final List<DailyOutcome> values,
    ) when values.isNotEmpty) {
      final DateTime today = ref.watch(todayProvider);
      final AsyncValue<List<ViceActivity>> activities = ref.watch(
        viceActivityRangeProvider(insightsRange(today)),
      );
      if (activities case AsyncError(:final error, :final stackTrace)) {
        return AsyncError<WeeklyInsights>(error, stackTrace);
      }
      final List<ViceActivity>? journal = activities.value;
      final List<Vice>? vices = ref.watch(viceListProvider).value;
      if (journal == null || vices == null) {
        return const AsyncLoading<WeeklyInsights>();
      }
      final String archived = ([
        for (final Vice v in vices)
          if (v.archived) v.id,
      ]..sort()).join(_archivedSeparator);
      final WeeklyInsights? result = ref
          .watch(
            _weeklyEngineProvider((
              activities: journal,
              health: values,
              end: reviewWeek(today).end,
              archived: archived,
            )),
          )
          .value;
      if (result == null) return const AsyncLoading<WeeklyInsights>();
      return AsyncData<WeeklyInsights>(result);
    }
    return AsyncData<WeeklyInsights>(WeeklyInsightsUnavailable(state));
  },
);
