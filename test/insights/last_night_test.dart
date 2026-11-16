import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/last_night_provider.dart';
import 'package:tracker/providers/today_provider.dart';

import '../insights_harness.dart';

final DateTime _today = insightsToday;

Map<DateTime, double> _nights(Map<int, double> byBack) => <DateTime, double>{
  for (final MapEntry<int, double> e in byBack.entries)
    addDays(_today, -e.key): e.value,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('compareLastNight', () {
    test(
      'last night against the median and 10th to 90th percentiles of the nights before',
      () {
        final NightCompare c = compareLastNight(
          _nights(<int, double>{
            0: 60,
            for (int back = 1; back <= 20; back++) back: 50.0 + back % 5,
            // Outside the baseline window.
            40: 99,
          }),
          _today,
        )!;
        expect(c.value, 60);
        expect(c.usual, 52);
        expect(c.low, 50);
        expect(c.high, 54);
        expect(c.side, NightSide.above);
      },
    );

    test('nothing without last night or with too few nights before', () {
      expect(
        compareLastNight(
          _nights(<int, double>{for (int b = 1; b <= 28; b++) b: 50}),
          _today,
        ),
        isNull,
      );
      expect(
        compareLastNight(
          _nights(<int, double>{
            0: 50,
            for (int b = 1; b < lastNightMinBaseline; b++) b: 50,
          }),
          _today,
        ),
        isNull,
      );
    });

    test('a value outside the usual range but shown as the usual is usual', () {
      const NightCompare c = NightCompare(
        value: 54.4,
        usual: 54,
        low: 54,
        high: 54.2,
      );
      expect(c.side, NightSide.usual);
      expect(
        const NightCompare(value: 52, usual: 54, low: 53, high: 55).side,
        NightSide.below,
      );
      expect(
        const NightCompare(value: 53.5, usual: 54, low: 53, high: 55).side,
        NightSide.usual,
      );
    });

    test('the difference is between the whole numbers shown', () {
      const NightCompare c = NightCompare(
        value: 56.6,
        usual: 54.4,
        low: 53,
        high: 55,
      );
      expect((c.shownValue, c.shownUsual, c.shownBy), (57, 54, 3));
      expect(c.side, NightSide.above);
      // Shown at the range's edge, so inside it.
      expect(
        const NightCompare(value: 44.6, usual: 48, low: 45, high: 51).side,
        NightSide.usual,
      );
    });
  });

  group('meansInBed', () {
    test('readings inside a sleep count to the night it ends on', () {
      final DateTime bedtime = addDays(
        _today,
        -1,
      ).add(const Duration(hours: 23));
      final List<HealthSample> bed = <HealthSample>[
        HealthSample(bedtime, _today.add(const Duration(hours: 7)), 0),
        // A nap ending after noon belongs to the next night.
        HealthSample(
          _today.add(const Duration(hours: 13)),
          _today.add(const Duration(hours: 14)),
          0,
        ),
      ];
      HealthSample at(DateTime t, double v) => HealthSample(t, t, v);
      final Map<DateTime, double> means = meansInBed(bed, <HealthSample>[
        at(bedtime.add(const Duration(hours: 1)), 40),
        at(_today.add(const Duration(hours: 3)), 50),
        // Awake, up and about.
        at(_today.add(const Duration(hours: 9)), 90),
        at(_today.add(const Duration(hours: 13, minutes: 30)), 30),
      ]);
      expect(means, <DateTime, double>{_today: 45, addDays(_today, 1): 30});
    });
  });

  group('lastNightProvider', () {
    ProviderContainer container(FakeHealthSource health) {
      final ProviderContainer c = ProviderContainer(
        overrides: [
          todayProvider.overrideWith(() => FixedToday(_today)),
          healthSourceProvider.overrideWithValue(health),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    List<DailyOutcome> nights(String metric, double last, double usual) =>
        <DailyOutcome>[
          DailyOutcome(_today, metric, last),
          for (int back = 1; back <= 28; back++)
            DailyOutcome(addDays(_today, -back), metric, usual + back % 3 - 1),
        ];

    test('reads nothing until Health is connected', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FakeHealthSource health = FakeHealthSource(
        read: HealthValues(nights(HealthMetric.sleepingHeartRate.id, 60, 54)),
      );
      final ProviderContainer c = container(health);
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      expect(await c.read(lastNightProvider.future), isNull);
      expect(health.reads, 0);
      expect(health.sampleCalls, 0);
      sub.close();
    });

    test('compares sleeping heart rate, time asleep and HRV in bed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        healthConnectedKey: true,
      });
      final List<HealthSample> bed = <HealthSample>[
        for (int back = 0; back <= 28; back++)
          HealthSample(
            addDays(_today, -back - 1).add(const Duration(hours: 23)),
            addDays(_today, -back).add(const Duration(hours: 7)),
            0,
          ),
      ];
      final List<HealthSample> hrv = <HealthSample>[
        for (int back = 0; back <= 28; back++)
          HealthSample(
            addDays(_today, -back).add(const Duration(hours: 3)),
            addDays(_today, -back).add(const Duration(hours: 3)),
            back == 0 ? 30 : 48.0 + back % 3,
          ),
      ];
      final FakeHealthSource health = FakeHealthSource(
        read: HealthValues(<DailyOutcome>[
          ...nights(HealthMetric.sleepingHeartRate.id, 58, 54),
          ...nights(HealthMetric.sleepAsleep.id, 430, 430),
        ]),
        sampleData: <HealthSampleMetric, List<HealthSample>>{
          HealthSampleMetric.bed: bed,
          HealthSampleMetric.heartRateVariabilitySDNN: hrv,
        },
      );
      final ProviderContainer c = container(health);
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      final LastNight night = (await withClock(
        Clock.fixed(_today.add(const Duration(hours: 8))),
        () => c.read(lastNightProvider.future),
      ))!;
      expect(night.sleepingHeartRate!.value, 58);
      expect(night.sleepingHeartRate!.side, NightSide.above);
      expect(night.asleep!.side, NightSide.usual);
      expect(night.heartRateVariability!.value, 30);
      expect(night.heartRateVariability!.usual, 49);
      expect(night.heartRateVariability!.side, NightSide.below);
      expect(health.reads, 2);
      sub.close();
    });

    test('heart rate never asked for still leaves the sleep row', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        healthConnectedKey: true,
      });
      final ProviderContainer c = container(
        _HeartNotDetermined(
          HealthValues(nights(HealthMetric.sleepAsleep.id, 300, 430)),
        ),
      );
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      final LastNight night = (await c.read(lastNightProvider.future))!;
      expect(night.sleepingHeartRate, isNull);
      expect(night.asleep!.side, NightSide.below);
      sub.close();
    });

    test('a failed read is no check, never an error', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        healthConnectedKey: true,
      });
      final ProviderContainer c = container(
        FakeHealthSource(
          failure: PlatformException(code: healthDatabaseInaccessible),
        ),
      );
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      expect(await c.read(lastNightProvider.future), isNull);
      expect(c.read(lastNightProvider).hasError, isFalse);
      sub.close();
    });

    Future<void> resume() async {
      final TestWidgetsFlutterBinding binding =
          TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
    }

    test('without last night\'s heart rate, reads again on resume', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        healthConnectedKey: true,
      });
      final FakeHealthSource health = FakeHealthSource(
        read: HealthValues(nights(HealthMetric.sleepAsleep.id, 400, 430)),
      );
      final ProviderContainer c = container(health);
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      expect((await c.read(lastNightProvider.future))!.asleep, isNotNull);
      final int reads = health.reads;

      await resume();
      await c.read(lastNightProvider.future);
      expect(health.reads, reads * 2);
      sub.close();
    });

    test('with it, a resume reads nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        healthConnectedKey: true,
      });
      final FakeHealthSource health = FakeHealthSource(
        read: HealthValues(nights(HealthMetric.sleepingHeartRate.id, 58, 54)),
      );
      final ProviderContainer c = container(health);
      final ProviderSubscription<AsyncValue<LastNight?>> sub = c.listen(
        lastNightProvider,
        (_, _) {},
      );
      await c.read(lastNightProvider.future);
      final int reads = health.reads;

      await resume();
      await c.read(lastNightProvider.future);
      expect(health.reads, reads);
      sub.close();
    });
  });

  group('morningProvider', () {
    bool morningAt(DateTime now) => withClock(Clock.fixed(now), () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      return c.read(morningProvider);
    });

    test('is true until local noon', () {
      expect(morningAt(_today.add(const Duration(hours: 6))), isTrue);
      expect(
        morningAt(_today.add(const Duration(hours: 11, minutes: 59))),
        isTrue,
      );
      expect(morningAt(_today.add(const Duration(hours: 12))), isFalse);
      expect(morningAt(_today.add(const Duration(hours: 23))), isFalse);
    });

    test('moves at noon and at midnight', () {
      fakeAsync((FakeAsync async) {
        final ProviderContainer c = ProviderContainer();
        expect(c.read(morningProvider), isTrue);
        async.elapse(const Duration(hours: 6));
        expect(c.read(morningProvider), isFalse);
        async.elapse(const Duration(hours: 11, minutes: 59));
        expect(c.read(morningProvider), isFalse);
        async.elapse(const Duration(minutes: 1));
        expect(c.read(morningProvider), isTrue);
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      }, initialTime: _today.add(const Duration(hours: 6)));
    });
  });
}

// Health as someone connected before heart rate was read sees it.
class _HeartNotDetermined extends FakeHealthSource {
  _HeartNotDetermined(HealthRead read) : super(read: read);

  @override
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  ) async {
    if (metrics.contains(HealthMetric.sleepingHeartRate)) {
      throw PlatformException(code: healthNotDetermined);
    }
    return super.dailyValues(metrics, start, end);
  }
}
