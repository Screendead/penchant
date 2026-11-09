import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/insights/health_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.screendead.penchant/health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final source = ChannelHealthSource(supported: true);
  final start = DateTime(2026, 11, 1);
  final end = DateTime(2026, 11, 8);

  test('sends the metric ids and local day keys', () async {
    answer((_) => <Object?>[]);
    await source.dailyValues(
      {HealthMetric.sleepAsleep, HealthMetric.stepCount},
      start,
      end,
    );
    expect(calls.single.method, 'dailyValues');
    expect(calls.single.arguments, {
      'metrics': ['sleepAsleep', 'stepCount'],
      'start': '2026-11-01',
      'end': '2026-11-08',
    });
  });

  test('decodes rows into daily outcomes at local midnight', () async {
    answer(
      (_) => <Object?>[
        {'date': '2026-11-02', 'metric': 'sleepAsleep', 'value': 431.5},
        {'date': '2026-11-02', 'metric': 'stepCount', 'value': 8012},
        {
          'date': '2026-11-03',
          'metric': 'heartRateVariabilitySDNN',
          'value': 48.25,
        },
      ],
    );
    final read = await source.dailyValues(
      {HealthMetric.sleepAsleep},
      start,
      end,
    );
    expect(read, isA<HealthValues>());
    expect((read as HealthValues).values, [
      DailyOutcome(DateTime(2026, 11, 2), 'sleepAsleep', 431.5),
      DailyOutcome(DateTime(2026, 11, 2), 'stepCount', 8012),
      DailyOutcome(DateTime(2026, 11, 3), 'heartRateVariabilitySDNN', 48.25),
    ]);
    expect(read.values.first.date.isUtc, isFalse);
  });

  test('no rows is no data, not zeros', () async {
    answer((_) => <Object?>[]);
    final read = await source.dailyValues(
      HealthMetric.values.toSet(),
      start,
      end,
    );
    expect((read as HealthValues).values, isEmpty);
  });

  test('drops malformed rows instead of reading them as values', () async {
    answer(
      (_) => <Object?>[
        {'date': '2026-11-02', 'metric': 'stepCount', 'value': 100},
        {'date': '2026-11-02', 'metric': 'stepCount'},
        {'date': '2026-11-02', 'metric': 'stepCount', 'value': '12'},
        {'date': '2026-11-02', 'metric': 'stepCount', 'value': double.nan},
        {'date': '2026-02-30', 'metric': 'stepCount', 'value': 1},
        {'date': '2 Nov', 'metric': 'stepCount', 'value': 1},
        {'date': '2026-11-02', 'metric': '', 'value': 1},
        'not a row',
        null,
      ],
    );
    final read = await source.dailyValues({HealthMetric.stepCount}, start, end);
    expect((read as HealthValues).values, [
      DailyOutcome(DateTime(2026, 11, 2), 'stepCount', 100),
    ]);
  });

  test('a null or non-list answer is no data', () async {
    for (final Object? reply in <Object?>[
      null,
      <String, Object>{'date': '2026-11-08', 'metric': 'stepCount', 'value': 1},
      'rows',
    ]) {
      answer((_) => reply);
      final read = await source.dailyValues(
        {HealthMetric.stepCount},
        start,
        end,
      );
      expect((read as HealthValues).values, isEmpty, reason: '$reply');
    }
  });

  test('the native unavailable code reads as unavailable', () async {
    answer((_) => throw PlatformException(code: 'unavailable'));
    expect(
      await source.dailyValues({HealthMetric.stepCount}, start, end),
      isA<HealthUnavailable>(),
    );
    expect(await source.isAvailable(), isFalse);
    expect(await source.requestAuthorization(), isFalse);
  });

  test('a missing channel, as on macOS, reads as unavailable', () async {
    expect(
      await source.dailyValues({HealthMetric.stepCount}, start, end),
      isA<HealthUnavailable>(),
    );
    expect(await source.isAvailable(), isFalse);
  });

  test('other native errors reach the caller', () async {
    answer((_) => throw PlatformException(code: 'authorization-failed'));
    expect(source.requestAuthorization(), throwsA(isA<PlatformException>()));
  });

  test('a locked device or an unasked read throws, not no data', () async {
    for (final code in [healthDatabaseInaccessible, healthNotDetermined]) {
      answer((_) => throw PlatformException(code: code));
      await expectLater(
        source.dailyValues({HealthMetric.sleepAsleep}, start, end),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    }
  });

  test('an empty range is no data, without a channel call', () async {
    answer((_) => throw PlatformException(code: 'bad-arguments'));
    for (final range in [(start, start), (end, start)]) {
      final read = await source.dailyValues(
        {HealthMetric.stepCount},
        range.$1,
        range.$2,
      );
      expect((read as HealthValues).values, isEmpty);
    }
    expect(calls, isEmpty);
  });

  test('off iOS it never calls the channel', () async {
    answer((_) => <Object?>[]);
    final offIOS = ChannelHealthSource();
    expect(
      await offIOS.dailyValues({HealthMetric.stepCount}, start, end),
      isA<HealthUnavailable>(),
    );
    expect(await offIOS.isAvailable(), isFalse);
    expect(await offIOS.requestAuthorization(), isFalse);
    expect(calls, isEmpty);
  });

  test('day keys round-trip and pad', () {
    expect(healthDayKey(DateTime(2026, 3, 9, 23, 59)), '2026-03-09');
    expect(parseHealthDayKey('2026-03-09'), DateTime(2026, 3, 9));
    expect(parseHealthDayKey('2026-3-9'), isNull);
  });

  group('samples', () {
    final from = DateTime(2026, 11, 8, 3);
    final to = DateTime(2026, 11, 8, 9);
    int us(DateTime t) => t.microsecondsSinceEpoch;
    Float64List triples(List<(DateTime, DateTime, double)> rows) =>
        Float64List.fromList([
          for (final r in rows) ...[
            us(r.$1).toDouble(),
            us(r.$2).toDouble(),
            r.$3,
          ],
        ]);

    test('sends the metric, microsecond bounds and limit', () async {
      answer((_) => {'samples': Float64List(0), 'next': null});
      await source.samples(HealthSampleMetric.heartRate, from, to, limit: 50);
      expect(calls.single.method, 'samples');
      expect(calls.single.arguments, {
        'metric': 'heartRate',
        'start': us(from),
        'end': us(to),
        'limit': 50,
      });
    });

    test('caps the limit at the native maximum', () async {
      answer((_) => {'samples': Float64List(0), 'next': null});
      await source.samples(
        HealthSampleMetric.heartRateVariabilitySDNN,
        from,
        to,
        limit: 1000000,
      );
      expect((calls.single.arguments as Map)['limit'], maxHealthSamplesPerCall);
    });

    test('decodes triples into local samples to the microsecond', () async {
      final t = DateTime(2026, 11, 8, 3, 0, 0, 0, 123);
      answer(
        (_) => {
          'samples': triples([
            (t, t, 61),
            (
              t.add(const Duration(minutes: 5)),
              t.add(const Duration(minutes: 6)),
              58.5,
            ),
          ]),
          'next': null,
        },
      );
      final read = await source.samples(HealthSampleMetric.heartRate, from, to);
      expect(read, isA<HealthSamples>());
      read as HealthSamples;
      expect(read.samples, [
        HealthSample(t, t, 61),
        HealthSample(
          t.add(const Duration(minutes: 5)),
          t.add(const Duration(minutes: 6)),
          58.5,
        ),
      ]);
      expect(read.samples.first.start.isUtc, isFalse);
      expect(read.next, isNull);
    });

    test('drops triples that are not finite or end before they start', () {
      final t = DateTime(2026, 11, 8, 4);
      final page = decodeHealthSamplePage({
        'samples': Float64List.fromList([
          us(t).toDouble(), us(t).toDouble(), 60,
          us(t).toDouble(), us(t).toDouble(), double.nan,
          double.infinity, us(t).toDouble(), 60,
          us(t).toDouble(), us(t).toDouble() - 1, 60,
          us(t).toDouble(), // a partial triple
        ]),
        'next': 'soon',
      });
      expect(page.samples, [HealthSample(t, t, 60)]);
      expect(page.next, isNull);
      expect(decodeHealthSamplePage(null).samples, isEmpty);
      expect(
        decodeHealthSamplePage({
          'samples': <Object?>[1.0, 2.0, 3.0],
        }).samples,
        isEmpty,
      );
    });

    test('pages by time until a page has no next start', () async {
      final a = DateTime(2026, 11, 8, 4);
      final b = DateTime(2026, 11, 8, 5);
      final c = DateTime(2026, 11, 8, 6);
      answer((call) {
        final start = (call.arguments as Map)['start'];
        if (start == us(from)) {
          return {
            'samples': triples([(a, a, 60)]),
            'next': us(b),
          };
        }
        if (start == us(b)) {
          return {
            'samples': triples([(b, b, 62)]),
            'next': us(c),
          };
        }
        return {
          'samples': triples([(c, c, 64)]),
          'next': null,
        };
      });
      final pages = await healthSamplePages(
        source,
        HealthSampleMetric.heartRate,
        from,
        to,
        limit: 1,
      ).toList();
      expect(
        [for (final call in calls) (call.arguments as Map)['start']],
        [us(from), us(b), us(c)],
      );
      expect(
        {for (final call in calls) (call.arguments as Map)['end']},
        {us(to)},
      );
      expect(
        [
          for (final p in pages)
            for (final s in (p as HealthSamples).samples) s.value,
        ],
        [60, 62, 64],
      );
    });

    test('a page whose next start does not move on throws', () async {
      answer((_) => {'samples': Float64List(0), 'next': us(from)});
      await expectLater(
        healthSamplePages(
          source,
          HealthSampleMetric.heartRate,
          from,
          to,
        ).toList(),
        throwsStateError,
      );
      expect(calls, hasLength(1));
    });

    test('unavailable is one unavailable page, and no paging', () async {
      answer((_) => throw PlatformException(code: 'unavailable'));
      final pages = await healthSamplePages(
        source,
        HealthSampleMetric.respiratoryRate,
        from,
        to,
      ).toList();
      expect(pages, [isA<HealthUnavailable>()]);
      expect(calls, hasLength(1));
    });

    test('a locked device throws, not no data', () async {
      answer((_) => throw PlatformException(code: healthDatabaseInaccessible));
      await expectLater(
        source.samples(HealthSampleMetric.heartRate, from, to),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            healthDatabaseInaccessible,
          ),
        ),
      );
    });

    test('an empty window, or off iOS, makes no channel call', () async {
      answer((_) => throw PlatformException(code: 'bad-arguments'));
      final read = await source.samples(HealthSampleMetric.heartRate, to, from);
      expect((read as HealthSamples).samples, isEmpty);
      expect(
        await healthSamplePages(
          source,
          HealthSampleMetric.heartRate,
          from,
          from,
        ).toList(),
        isEmpty,
      );
      expect(
        await ChannelHealthSource().samples(
          HealthSampleMetric.heartRate,
          from,
          to,
        ),
        isA<HealthUnavailable>(),
      );
      expect(calls, isEmpty);
    });
  });

  // HealthChannel.swift matches this id as a literal.
  test('sleeping heart rate is a daily metric the channel is asked for', () {
    expect(HealthMetric.sleepingHeartRate.id, 'sleepingHeartRate');
    expect(
      decodeHealthRows([
        {'date': '2026-11-08', 'metric': 'sleepingHeartRate', 'value': 52.5},
      ]),
      [DailyOutcome(DateTime(2026, 11, 8), 'sleepingHeartRate', 52.5)],
    );
  });
}
