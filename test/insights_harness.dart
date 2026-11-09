import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';

final DateTime insightsToday = DateTime(2026, 11, 8);

class FixedToday extends Today {
  FixedToday(this._day);

  final DateTime _day;

  @override
  DateTime build() => _day;
}

class FakeHealthSource implements HealthSource {
  FakeHealthSource({this.available = true, this.read, this.failure});

  final bool available;
  final HealthRead? read;
  final PlatformException? failure;
  int authorizationRequests = 0;
  int reads = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequests++;
    return available;
  }

  @override
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  ) async {
    reads++;
    if (failure case final PlatformException e) throw e;
    return read ?? const HealthValues(<DailyOutcome>[]);
  }
}

final List<Vice> insightsVices = <Vice>[
  fakeVice('coffee', name: 'Coffee'),
  fakeVice('tea', name: 'Tea'),
  fakeVice('water', name: 'Water'),
];

/// 120 days of Coffee and Tea on independent days, and Water for the last ten
/// only. The night after a Coffee day has [deepSleepEffect] minutes of deep
/// sleep added and the next day's resting heart rate [heartRateEffect] bpm;
/// nothing follows Tea.
({List<ViceActivity> activities, List<DailyOutcome> health}) insightsJournal({
  double deepSleepEffect = -18,
  double heartRateEffect = 2,
  bool teaWithCoffee = false,
  int seed = 7,
}) {
  final Random random = Random(seed);
  double noise(double spread) =>
      (random.nextDouble() + random.nextDouble() - 1) * spread;
  final List<ViceActivity> activities = <ViceActivity>[];
  final List<DailyOutcome> health = <DailyOutcome>[];
  bool coffeeBefore = false;
  for (int back = 120; back >= 0; back--) {
    final DateTime day = addDays(insightsToday, -back);
    health
      ..add(
        DailyOutcome(
          day,
          HealthMetric.sleepDeep.id,
          70 + noise(10) + (coffeeBefore ? deepSleepEffect : 0),
        ),
      )
      ..add(DailyOutcome(day, HealthMetric.sleepAsleep.id, 420 + noise(30)))
      ..add(
        DailyOutcome(
          day,
          HealthMetric.restingHeartRate.id,
          58 + noise(1.5) + (coffeeBefore ? heartRateEffect : 0),
        ),
      );
    final bool coffee = random.nextBool();
    final bool tea = teaWithCoffee ? coffee : random.nextBool();
    final DateTime at = day.add(const Duration(hours: 9));
    if (coffee) activities.add(fakeActivity('coffee', 2, at));
    if (tea) activities.add(fakeActivity('tea', 1, at));
    if (back < 10) activities.add(fakeActivity('water', 3, at));
    coffeeBefore = coffee;
  }
  return (activities: activities, health: health);
}

List<Override> insightsOverrides({
  required HealthSource health,
  AsyncValue<List<ViceActivity>>? activities,
  AsyncValue<List<Vice>>? vices,
  void Function()? onJournalOpened,
  InsightsRunner? runner,
}) => <Override>[
  todayProvider.overrideWith(() => FixedToday(insightsToday)),
  healthSourceProvider.overrideWithValue(health),
  insightsRunnerProvider.overrideWithValue(
    runner ?? (InsightsInput input) async => computeInsights(input),
  ),
  viceListProvider.overrideWithValue(
    vices ?? AsyncData<List<Vice>>(insightsVices),
  ),
  viceActivityRangeProvider.overrideWith((Ref ref, ActivityRange range) {
    onJournalOpened?.call();
    return activities ??
        AsyncData<List<ViceActivity>>(insightsJournal().activities);
  }),
];
