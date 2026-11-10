import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/stats.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/weekly_review_provider.dart';

import 'fakes.dart';

/// A Tuesday, so the reviewed week is Monday 2 to Sunday 8 November 2026.
final DateTime reviewToday = DateTime(2026, 11, 10);

Vice _vice(String id, String name, Unit unit, int order) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime(2026, 1, order)),
  archived: false,
);

final List<Vice> reviewVices = <Vice>[
  _vice('coffee', 'Coffee', Unit.drink, 1),
  _vice('alcohol', 'Alcohol', Unit.drink, 2),
  _vice('scroll', 'Doomscrolling', Unit.minute, 3),
];

/// Five weeks of the three habits: coffee mornings, evening drinks, and
/// scrolling late, with a trigger now and then.
List<ViceActivity> reviewJournal() {
  final ReviewWeek week = reviewWeek(reviewToday);
  final DateTime start = reviewRange(week).start;
  final List<ViceActivity> out = <ViceActivity>[];
  for (int d = 0; d < 35; d++) {
    final DateTime day = addDays(start, d);
    out.add(fakeActivity('coffee', 1, day.add(const Duration(hours: 8))));
    if (d % 2 == 0) {
      out.add(
        fakeActivity(
          'coffee',
          1,
          day.add(const Duration(hours: 14, minutes: 30)),
          triggers: const <String>['work/meeting'],
        ),
      );
    }
    if (d % 3 == 0 || (d >= 28 && d.isEven)) {
      out.add(
        fakeActivity(
          'alcohol',
          2,
          day.add(const Duration(hours: 20, minutes: 15)),
          triggers: const <String>['with friends'],
        ),
      );
    }
    out.add(
      fakeActivity(
        'scroll',
        20 + (d % 4) * 10,
        day.add(const Duration(hours: 22, minutes: 40)),
      ),
    );
  }
  return out;
}

HabitFinding reviewFinding(String habitId, String metricId, double effect) =>
    HabitFinding(
      habitId: habitId,
      metricId: metricId,
      lagDays: 1,
      usableDays: 90,
      exposedDays: 40,
      raw: null,
      effect: effect,
      interval: Interval(effect * 1.5, effect * 0.5),
      standardized: effect / 20,
      pValue: 0.001,
    );

final InsightCard _alcoholSleep = InsightCard(
  family: MetricFamily.sleep,
  headline: reviewFinding('alcohol', 'sleepAsleep', -24),
);
final InsightCard _coffeeHeart = InsightCard(
  family: MetricFamily.heart,
  headline: reviewFinding('coffee', 'restingHeartRate', 2),
);
final InsightCard _scrollSleep = InsightCard(
  family: MetricFamily.sleep,
  headline: reviewFinding('scroll', 'sleepREM', -9),
);

final WeeklyInsights reviewInsights = WeeklyInsightsComputed(
  changes: (
    started: <InsightCard>[_alcoholSleep],
    stopped: <InsightCard>[_coffeeHeart],
    holding: <InsightCard>[_scrollSleep],
  ),
  collecting: const <HabitRefusal>[
    HabitRefusal(
      habitId: 'scroll',
      metricId: 'sleepAsleep',
      lagDays: 1,
      usableDays: 12,
      exposedDays: 12,
      raw: null,
      reason: RefusalReason.tooFewDays,
    ),
  ],
  floors: const <String, double>{},
);

List<Override> reviewOverrides({
  List<ViceActivity>? journal,
  WeeklyInsights? insights,
}) => <Override>[
  viceListProvider.overrideWithValue(AsyncData<List<Vice>>(reviewVices)),
  weeklyReviewProvider.overrideWithValue(
    AsyncData<WeeklyReview>(
      buildWeeklyReview(
        week: reviewWeek(reviewToday),
        vices: reviewVices,
        activities: journal ?? reviewJournal(),
      ),
    ),
  ),
  weeklyInsightsProvider.overrideWithValue(
    AsyncData<WeeklyInsights>(insights ?? reviewInsights),
  ),
];
