import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/health_sync.dart';
import 'package:tracker/insights/insights_report.dart';

import 'insights_harness.dart';

class _FailingFile implements HealthStoreFile {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String contents) async => throw StateError('disk full');
}

void main() {
  final DateTime today = DateTime(2026, 11, 10);
  final DateTime nov8 = DateTime(2026, 11, 8);
  final Set<HealthMetric> metrics = <HealthMetric>{
    HealthMetric.stepCount,
    HealthMetric.sleepAsleep,
  };
  final List<DailyOutcome> health = <DailyOutcome>[
    DailyOutcome(DateTime(2025, 3, 1), 'stepCount', 4000),
    DailyOutcome(nov8, 'stepCount', 9000),
    DailyOutcome(nov8, 'sleepAsleep', 420),
    DailyOutcome(DateTime(2026, 11, 9), 'sleepAsleep', 400),
  ];

  Future<List<DailyOutcome>> sync(
    FakeHealthSource source,
    HealthStoreFile file, {
    DateTime? on,
  }) async {
    final DateTime day = on ?? today;
    final HealthRead? read = await syncHealthDaily(
      source: source,
      file: file,
      metrics: metrics,
      range: insightsRange(day),
      today: day,
    );
    return (read! as HealthValues).values;
  }

  Map<String, double> byKey(List<DailyOutcome> values) => <String, double>{
    for (final DailyOutcome v in values)
      '${healthDayKey(v.date)} ${v.metricId}': v.value,
  };

  test('the first sync reads every year and keeps it', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    final List<DailyOutcome> got = await sync(source, file);
    expect(source.dailyCalls, hasLength(insightsHealthChunks(insightsRange(today)).length));
    expect(source.dailyCalls.every((c) => setEquals(c.metrics, metrics)), isTrue);
    expect(byKey(got), byKey(health));
    expect(file.writes, 1);
    expect(source.handled, [1]);
  });

  test('later syncs read only the changed days', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = HealthChanges(
      generation: 7,
      days: <String, Set<DateTime>>{
        'stepCount': <DateTime>{nov8},
      },
    );
    final List<DailyOutcome> got = await sync(source, file);
    expect(source.dailyCalls, hasLength(1));
    expect(source.dailyCalls.single.metrics, {HealthMetric.stepCount});
    expect(source.dailyCalls.single.start, nov8);
    expect(source.dailyCalls.single.end, addDays(nov8, 1));
    expect(byKey(got), byKey(health));
    expect(source.handled.last, 7);
  });

  test('nothing changed reads nothing', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = const HealthChanges(generation: 2);
    expect(byKey(await sync(source, file)), byKey(health));
    expect(source.dailyCalls, isEmpty);
  });

  test('a changed night rereads its calendar year of sleep', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = HealthChanges(
      generation: 2,
      days: <String, Set<DateTime>>{
        'sleepAsleep': <DateTime>{nov8},
      },
    );
    await sync(source, file);
    expect(source.dailyCalls.single.metrics, {HealthMetric.sleepAsleep});
    expect(source.dailyCalls.single.start, DateTime(2026));
    expect(source.dailyCalls.single.end, addDays(today, 1));
  });

  test('a metric marked whole is read in full, alone', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = const HealthChanges(
      generation: 2,
      whole: <String>{'stepCount'},
    );
    await sync(source, file);
    expect(
      source.dailyCalls,
      hasLength(insightsHealthChunks(insightsRange(today)).length),
    );
    expect(
      source.dailyCalls.every(
        (c) => setEquals(c.metrics, {HealthMetric.stepCount}),
      ),
      isTrue,
    );
  });

  test('a value gone from Health on a reread leaves the store', () async {
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(FakeHealthSource(read: HealthValues(health)), file);
    final FakeHealthSource source = FakeHealthSource(
      read: HealthValues(<DailyOutcome>[
        for (final DailyOutcome v in health)
          if (!(v.date == nov8 && v.metricId == 'stepCount')) v,
      ]),
    )..nextChanges = HealthChanges(
        generation: 2,
        days: <String, Set<DateTime>>{
          'stepCount': <DateTime>{nov8},
        },
      );
    final Map<String, double> got = byKey(await sync(source, file));
    expect(got.containsKey('2026-11-08 stepCount'), isFalse);
    expect(got['2026-11-08 sleepAsleep'], 420);
  });

  test('a new day is read for every metric', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = const HealthChanges(generation: 2);
    final DateTime tomorrow = addDays(today, 1);
    await sync(source, file, on: tomorrow);
    expect(source.dailyCalls, hasLength(1));
    expect(source.dailyCalls.single.metrics, metrics);
    expect(source.dailyCalls.single.start, addDays(today, 1));
    expect(source.dailyCalls.single.end, addDays(tomorrow, 1));
  });

  test('an old store is read again in full', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    await sync(source, file);
    source.dailyCalls.clear();
    source.nextChanges = const HealthChanges(generation: 2);
    final DateTime later = addDays(today, healthStoreRebuildDays + 1);
    await sync(source, file, on: later);
    expect(
      source.dailyCalls,
      hasLength(insightsHealthChunks(insightsRange(later)).length),
    );
  });

  test('a store that cannot be written is not acknowledged', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health));
    expect(byKey(await sync(source, _FailingFile())), byKey(health));
    expect(source.handled, isEmpty);
  });

  test('a failed read neither writes nor acknowledges', () async {
    final MemoryHealthStoreFile file = MemoryHealthStoreFile();
    final FakeHealthSource source = FakeHealthSource(
      failure: PlatformException(code: healthDatabaseInaccessible),
    );
    await expectLater(sync(source, file), throwsA(isA<PlatformException>()));
    expect(file.writes, 0);
    expect(source.handled, isEmpty);
  });

  test('an unreadable store is read again in full', () async {
    final FakeHealthSource source = FakeHealthSource(read: HealthValues(health))
      ..nextChanges = const HealthChanges(generation: 2);
    final MemoryHealthStoreFile file = MemoryHealthStoreFile()
      ..contents = '{"version": 1';
    expect(byKey(await sync(source, file)), byKey(health));
    expect(
      source.dailyCalls,
      hasLength(insightsHealthChunks(insightsRange(today)).length),
    );
  });

  test('the store round-trips', () {
    final HealthDailyStore store = HealthDailyStore(
      metrics: const <String>{'stepCount'},
      through: today,
      built: nov8,
      values: <String, Map<DateTime, double>>{
        'stepCount': <DateTime, double>{nov8: 9000.5},
      },
    );
    final HealthDailyStore? back = HealthDailyStore.decode(store.encode());
    expect(back?.through, today);
    expect(back?.built, nov8);
    expect(back?.values['stepCount'], {nov8: 9000.5});
  });

  group('decodeHealthChanges', () {
    test('reads days and whole metrics', () {
      final HealthChanges c = decodeHealthChanges(<String, Object?>{
        'generation': 4,
        'days': <Object?, Object?>{
          'stepCount': <Object?>['2026-11-08'],
        },
        'whole': <Object?>['sleepAsleep'],
      }, metrics);
      expect(c.generation, 4);
      expect(c.days['stepCount'], {nov8});
      expect(c.whole, {'sleepAsleep'});
    });

    test('anything unreadable reads every metric in full', () {
      final HealthChanges c = decodeHealthChanges(<String, Object?>{
        'generation': 4,
        'days': <Object?, Object?>{
          'stepCount': <Object?>['not a day'],
        },
        'whole': <Object?>[],
      }, metrics);
      expect(c.whole, {'stepCount', 'sleepAsleep'});
      expect(c.generation, -1);
    });
  });
}
