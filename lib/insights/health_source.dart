import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Health values stay on the device. Nothing from this file may reach
// Firestore, analytics or crash reports, so its failures are returned to the
// caller rather than passed to reportError.

/// One day's value of one outcome, for the insights engine.
@immutable
class DailyOutcome {
  const DailyOutcome(this.date, this.metricId, this.value);

  /// Local midnight of the day. A sleep value for day D is the night that
  /// ended on D: sleep that ended between noon on D-1 and noon on D, so an
  /// afternoon nap counts towards the following night.
  final DateTime date;

  /// A [HealthMetric.id], or another source's id.
  final String metricId;

  final double value;

  @override
  bool operator ==(Object other) =>
      other is DailyOutcome &&
      other.date == date &&
      other.metricId == metricId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(date, metricId, value);

  @override
  String toString() => 'DailyOutcome($date, $metricId, $value)';
}

/// What ios/Runner/HealthChannel.swift reads, one value per day. The sleep
/// metrics are minutes, merged across sources so that overlapping samples
/// count once; the stages (core, deep, REM) come from iOS 16 and later.
enum HealthMetric {
  sleepInBed('sleepInBed'),
  sleepAsleep('sleepAsleep'),
  sleepAwake('sleepAwake'),
  sleepCore('sleepCore'),
  sleepDeep('sleepDeep'),
  sleepREM('sleepREM'),

  /// The day's average, in milliseconds.
  heartRateVariabilitySDNN('heartRateVariabilitySDNN'),

  /// The day's average, in beats per minute.
  restingHeartRate('restingHeartRate'),

  /// The day's average, in breaths per minute.
  respiratoryRate('respiratoryRate'),

  /// The day's average, as a fraction from 0 to 1.
  oxygenSaturation('oxygenSaturation'),

  /// The night's average, in degrees Celsius. iOS 16 and later.
  appleSleepingWristTemperature('appleSleepingWristTemperature'),

  /// The day's total.
  stepCount('stepCount'),

  /// The day's total, in kilocalories.
  activeEnergyBurned('activeEnergyBurned');

  const HealthMetric(this.id);

  final String id;
}

sealed class HealthRead {
  const HealthRead();
}

/// No Health on this platform or device (macOS, tests, some iPads).
final class HealthUnavailable extends HealthRead {
  const HealthUnavailable();
}

/// A day missing from [values] has no data, which is not a zero: HealthKit
/// answers a refused read with no samples, the same as an empty one.
final class HealthValues extends HealthRead {
  const HealthValues(this.values);

  final List<DailyOutcome> values;
}

abstract interface class HealthSource {
  Future<bool> isAvailable();

  /// Shows the system's Health sheet for every [HealthMetric]. True once it
  /// completed, which says nothing about what was allowed; false when Health
  /// is unavailable.
  Future<bool> requestAuthorization();

  /// Values for the days from [start] up to but not including [end].
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  );
}

class ChannelHealthSource implements HealthSource {
  ChannelHealthSource({
    MethodChannel channel = const MethodChannel(
      'com.screendead.penchant/health',
    ),
    bool? supported,
  }) : _channel = channel,
       _supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final MethodChannel _channel;
  final bool _supported;

  @override
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return false;
      rethrow;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestAuthorization() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestAuthorization') ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return false;
      rethrow;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  ) async {
    if (!_supported) return const HealthUnavailable();
    final Object? rows;
    try {
      rows = await _channel.invokeMethod<Object?>('dailyValues', {
        'metrics': [for (final m in metrics) m.id],
        'start': healthDayKey(start),
        'end': healthDayKey(end),
      });
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return const HealthUnavailable();
      rethrow;
    } on MissingPluginException {
      return const HealthUnavailable();
    }
    return HealthValues(decodeHealthRows(rows));
  }
}

String healthDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime? parseHealthDayKey(String key) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// Drops any row that is not a known date, a metric id and a finite number,
/// rather than read it as a value.
@visibleForTesting
List<DailyOutcome> decodeHealthRows(Object? rows) {
  if (rows is! List) return const <DailyOutcome>[];
  return [
    for (final row in rows)
      if (row case {
        'date': final String date,
        'metric': final String metric,
        'value': final num value,
      })
        if (parseHealthDayKey(date) case final DateTime day)
          if (metric.isNotEmpty && value.isFinite)
            DailyOutcome(day, metric, value.toDouble()),
  ];
}
