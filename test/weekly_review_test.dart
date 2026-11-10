import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/trigger_usage.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/weekly_review.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/providers/weekly_review_provider.dart';

import 'fakes.dart';
import 'insights_harness.dart';
import 'weekly_review_fixture.dart';

HabitRefusal _refusal(String habitId, RefusalReason reason) => HabitRefusal(
  habitId: habitId,
  metricId: 'sleepAsleep',
  lagDays: 1,
  usableDays: 12,
  exposedDays: 6,
  raw: null,
  reason: reason,
);

void main() {
  test('the reviewed week is the last whole Monday to Sunday', () {
    final ReviewWeek tuesday = reviewWeek(DateTime(2026, 11, 10, 15));
    expect(tuesday.start, DateTime(2026, 11, 2));
    expect(tuesday.end, DateTime(2026, 11, 9));
    // On Monday itself, the week that ended at midnight.
    expect(reviewWeek(DateTime(2026, 11, 9)).start, DateTime(2026, 11, 2));
    expect(reviewWeek(DateTime(2026, 11, 8, 23)).start, DateTime(2026, 10, 26));
    expect(reviewRange(tuesday).start, DateTime(2026, 10, 5));
  });

  test('totals sit beside the mean of the four weeks before', () {
    final WeeklyReview review = buildWeeklyReview(
      week: reviewWeek(reviewToday),
      vices: reviewVices,
      activities: reviewJournal(),
    );
    final HabitWeek coffee = review.habits.first;
    expect(coffee.vice.id, 'coffee');
    expect(coffee.weeks, <num>[11, 10, 11, 10, 11]);
    expect(coffee.total, 11);
    expect(coffee.entries, 11);
    expect(coffee.usual, 10.5);
    expect(
      review.habits.map((HabitWeek h) => h.vice.id),
      <String>['coffee', 'alcohol', 'scroll'],
    );
  });

  test('busiest hours break a tie by the earlier hour', () {
    final WeeklyReview review = buildWeeklyReview(
      week: reviewWeek(reviewToday),
      vices: reviewVices,
      activities: reviewJournal(),
    );
    expect(review.busiest(3), <HourCount>[
      (hour: 8, entries: 7),
      (hour: 22, entries: 7),
      (hour: 20, entries: 5),
    ]);
    expect(review.entries, 7 + 4 + 5 + 7);
  });

  test('triggers count the reviewed week only, most first', () {
    final WeeklyReview review = buildWeeklyReview(
      week: reviewWeek(reviewToday),
      vices: reviewVices,
      activities: reviewJournal(),
    );
    expect(review.triggers, <TriggerCount>[
      (label: 'with friends', entries: 5),
      (label: triggerDisplay('work/meeting'), entries: 4),
    ]);
  });

  test('a habit made during the window has no usual from before it', () {
    final ReviewWeek week = reviewWeek(reviewToday);
    final Vice newer = Vice(
      id: 'tea',
      name: 'Tea',
      unit: Unit.item,
      ownerID: ownerID,
      createdAt: Timestamp.fromDate(week.start),
    );
    final Vice archived = fakeVice('gone', archived: true);
    final WeeklyReview review = buildWeeklyReview(
      week: week,
      vices: <Vice>[newer, archived],
      activities: <ViceActivity>[
        fakeActivity('tea', 3, week.start.add(const Duration(hours: 9))),
      ],
    );
    expect(review.habits.single.vice.id, 'tea');
    expect(review.habits.single.usual, isNull);
    expect(review.habits.single.total, 3);
  });

  test('insight changes say what started, stopped and held', () {
    final HabitFinding wine = reviewFinding('alcohol', 'sleepAsleep', -24);
    final HabitFinding coffee = reviewFinding('coffee', 'restingHeartRate', 2);
    final HabitFinding scroll = reviewFinding('scroll', 'sleepREM', -9);
    final InsightChanges changes = insightChanges(
      InsightsReport(
        findings: <HabitFinding>[coffee, scroll],
        refused: const <HabitRefusal>[],
      ),
      InsightsReport(
        findings: <HabitFinding>[wine, scroll],
        refused: const <HabitRefusal>[],
      ),
    );
    expect(changes.started.single.headline, wine);
    expect(changes.stopped.single.headline, coffee);
    expect(changes.holding.single.headline, scroll);
  });

  test('still collecting lists only habits short of days', () {
    final List<HabitRefusal> collecting = stillCollecting(
      InsightsReport(
        findings: const <HabitFinding>[],
        refused: <HabitRefusal>[
          _refusal('coffee', RefusalReason.tooFewDays),
          _refusal('alcohol', RefusalReason.chance),
        ],
      ),
    );
    expect(collecting.single.habitId, 'coffee');
  });

  test('the provider reads the reviewed week and the four before', () {
    final List<ActivityRange> asked = <ActivityRange>[];
    final ProviderContainer container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(() => FixedToday(reviewToday)),
        viceListProvider.overrideWithValue(
          AsyncData<List<Vice>>(reviewVices),
        ),
        viceActivityRangeProvider.overrideWith((ref, ActivityRange range) {
          asked.add(range);
          return AsyncData<List<ViceActivity>>(reviewJournal());
        }),
      ],
    );
    addTearDown(container.dispose);
    final WeeklyReview review = container.read(weeklyReviewProvider).value!;
    expect(asked, <ActivityRange>[reviewRange(reviewWeek(reviewToday))]);
    expect(review.habits.first.total, 11);
  });
}
