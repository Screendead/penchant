import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/insights/daily_series.dart' show HabitUse;
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/last_night_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';
import 'insights/hours_after_synthetic.dart';

final DateTime insightsToday = DateTime(2026, 11, 8);

/// The channel calls one Health read of the Insights range makes.
final int insightsHealthCalls = insightsHealthChunks(
  insightsRange(insightsToday),
).length;

class FixedToday extends Today {
  FixedToday(this._day);

  final DateTime _day;

  @override
  DateTime build() => _day;
}

class FakeHealthSource implements HealthSource {
  FakeHealthSource({
    this.available = true,
    this.read,
    this.failure,
    this.status = HealthRequestStatus.unnecessary,
    this.sampleData = const <HealthSampleMetric, List<HealthSample>>{},
    this.sampleFailure,
    this.sampleGate,
  });

  final PlatformException? sampleFailure;

  /// When set, every sample read waits for it.
  final Future<void>? sampleGate;

  final bool available;

  /// Sorted by start; served in pages as the channel does.
  final Map<HealthSampleMetric, List<HealthSample>> sampleData;
  int sampleCalls = 0;
  int samplesServed = 0;
  final HealthRead? read;
  final PlatformException? failure;

  /// Becomes [HealthRequestStatus.unnecessary] once the sheet is shown.
  HealthRequestStatus status;
  int authorizationRequests = 0;
  int statusChecks = 0;
  int reads = 0;
  Set<HealthMetric>? lastMetrics;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<HealthRequestStatus> requestStatus() async {
    statusChecks++;
    return status;
  }

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequests++;
    if (available) status = HealthRequestStatus.unnecessary;
    return available;
  }

  @override
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  ) async {
    reads++;
    lastMetrics = metrics;
    if (failure case final PlatformException e) throw e;
    return switch (read) {
      HealthValues(:final List<DailyOutcome> values) =>
        HealthValues(<DailyOutcome>[
          for (final DailyOutcome v in values)
            if (!v.date.isBefore(start) && v.date.isBefore(end)) v,
        ]),
      final HealthRead other => other,
      null => const HealthValues(<DailyOutcome>[]),
    };
  }

  @override
  Future<HealthSampleRead> samples(
    HealthSampleMetric metric,
    DateTime start,
    DateTime end, {
    int limit = maxHealthSamplesPerCall,
  }) async {
    sampleCalls++;
    if (sampleGate case final Future<void> gate) await gate;
    if (failure ?? sampleFailure case final PlatformException e) throw e;
    final List<HealthSample> page = <HealthSample>[];
    for (final HealthSample s in sampleData[metric] ?? const <HealthSample>[]) {
      if (s.start.isBefore(start) || !s.start.isBefore(end)) continue;
      if (page.length == limit) {
        samplesServed += page.length;
        return HealthSamples(page, next: s.start);
      }
      page.add(s);
    }
    samplesServed += page.length;
    return HealthSamples(page);
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
  double heartRateEffect = 6,
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
  LastNight? lastNight,
}) => <Override>[
  // Its own reads are tested in last_night_test.dart; here they would join
  // the counts of the engine's.
  lastNightProvider.overrideWith((Ref ref) async => lastNight),
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

// A year of Coffee, Tea and Water ending the day before insightsToday, with
// heart rate rising one to two hours after Coffee.
Synthetic insightsHoursYear() {
  final Synthetic s = synthetic(
    11,
    days: 365,
    habits: const <String, HabitPattern>{
      'coffee': (chance: 0.6, from: 6 * 60, to: 11 * 60),
      'tea': (chance: 0.5, from: 13 * 60, to: 18 * 60),
      'water': (chance: 1, from: 8 * 60, to: 20 * 60),
    },
    effect: (h, m) => h == 'coffee' && m >= 60 && m < 120 ? 6 : 0,
  );
  // Shift so the last day is the day before insightsToday.
  final Duration shift = addDays(
    insightsToday,
    -365,
  ).difference(syntheticStart);
  HealthSample moved(HealthSample x) =>
      HealthSample(x.start.add(shift), x.end.add(shift), x.value);
  return Synthetic(
    <HabitUse>[
      for (final HabitUse u in s.uses)
        HabitUse(habitId: u.habitId, at: u.at.add(shift), amount: u.amount),
    ],
    <String, List<HealthSample>>{
      for (final MapEntry<String, List<HealthSample>> e in s.samples.entries)
        e.key: <HealthSample>[for (final x in e.value) moved(x)],
    },
    insightsToday,
  );
}
