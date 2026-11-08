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
    answer((_) => null);
    final read = await source.dailyValues({HealthMetric.stepCount}, start, end);
    expect((read as HealthValues).values, isEmpty);
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
}
