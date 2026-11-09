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
  /// ended on D: each sleep, taken whole, that ended between noon on D-1 and
  /// noon on D, so an afternoon nap counts towards the following night. The
  /// night metrics ([HealthMetric.respiratoryRate] and
  /// [HealthMetric.appleSleepingWristTemperature]) use the same noon-to-noon
  /// window, so they line up with that night's sleep.
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

  /// When the night's main sleep (the one with the most asleep time, or in
  /// bed when none has any, so not a nap) began, with any part of the night
  /// less than an hour before it: its first asleep moment, or its first in
  /// bed when it has no asleep time, from the same source as the minutes
  /// above. In clock minutes after the last noon before it, so 23:00 is 660,
  /// 01:00 is 780, and a sleep that ends after noon still reads 0 to 1440.
  /// The insights engine holds it fixed for the sleep minutes; it is not an
  /// outcome of its own.
  sleepOnset('sleepOnset'),

  /// When the night's main sleep ended, as [sleepOnset] measures it and from
  /// the same noon: its last asleep moment, or its last in bed.
  sleepEnd('sleepEnd'),

  /// The day's average, in milliseconds.
  heartRateVariabilitySDNN('heartRateVariabilitySDNN'),

  /// The day's average, in beats per minute.
  restingHeartRate('restingHeartRate'),

  /// The night's average, noon to noon like sleep, in breaths per minute.
  respiratoryRate('respiratoryRate'),

  /// The day's average, as a fraction from 0 to 1.
  oxygenSaturation('oxygenSaturation'),

  /// The night's average, noon to noon like sleep, in degrees Celsius. iOS 16
  /// and later.
  appleSleepingWristTemperature('appleSleepingWristTemperature'),

  /// The day's total.
  stepCount('stepCount'),

  /// The day's total, in kilocalories.
  activeEnergyBurned('activeEnergyBurned'),

  /// The plain mean of the heart rate samples inside the night's asleep time
  /// (core, deep, REM or unspecified; not in bed or awake), keyed to the night
  /// like the sleep metrics, in beats per minute. A sample is inside when its
  /// midpoint is. A night with no asleep time or no sample in it has no value,
  /// as has every night for someone never asked for heart rate.
  sleepingHeartRate('sleepingHeartRate');

  const HealthMetric(this.id);

  final String id;
}

/// What [HealthSource.samples] reads, timestamped rather than per day.
enum HealthSampleMetric {
  /// Beats per minute.
  heartRate('heartRate'),

  /// Milliseconds.
  heartRateVariabilitySDNN('heartRateVariabilitySDNN'),

  /// Breaths per minute.
  respiratoryRate('respiratoryRate');

  const HealthSampleMetric(this.id);

  final String id;
}

/// One reading as Health stored it. Most heart rate readings are an instant,
/// with [end] equal to [start].
@immutable
class HealthSample {
  const HealthSample(this.start, this.end, this.value);

  /// Local, to the microsecond.
  final DateTime start;
  final DateTime end;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is HealthSample &&
      other.start == start &&
      other.end == end &&
      other.value == value;

  @override
  int get hashCode => Object.hash(start, end, value);

  @override
  String toString() => 'HealthSample($start, $end, $value)';
}

sealed class HealthRead {
  const HealthRead();
}

sealed class HealthSampleRead {
  const HealthSampleRead();
}

/// No Health on this platform or device (macOS, tests, some iPads).
final class HealthUnavailable extends HealthRead implements HealthSampleRead {
  const HealthUnavailable();
}

/// Samples whose start is from the page's start up to [next], or to the end
/// of the window asked for when [next] is null. Missing samples are no data.
final class HealthSamples extends HealthSampleRead {
  const HealthSamples(this.samples, {this.next});

  /// Sorted by start.
  final List<HealthSample> samples;

  /// Where the next page starts, when this one was full.
  final DateTime? next;
}

/// A day missing from [values] has no data, which is not a zero: HealthKit
/// answers a read the person refused with no samples, the same as an empty
/// one. A read HealthKit could not make throws instead (see
/// [HealthSource.dailyValues]).
final class HealthValues extends HealthRead {
  const HealthValues(this.values);

  final List<DailyOutcome> values;
}

const healthDatabaseInaccessible = 'database-inaccessible';
const healthNotDetermined = 'not-determined';

/// HealthKit's answer to whether [HealthSource.requestAuthorization] would show
/// the sheet: it shows only the types the person was never asked about.
enum HealthRequestStatus { shouldRequest, unnecessary, unknown }

abstract interface class HealthSource {
  Future<bool> isAvailable();

  /// Whether the read types hold one the person was never asked about. Says
  /// nothing about what was allowed. [HealthRequestStatus.unknown] when Health
  /// is unavailable or HealthKit cannot tell.
  Future<HealthRequestStatus> requestStatus();

  /// Shows the system's Health sheet for every [HealthMetric]. True once it
  /// completed, which says nothing about what was allowed; false when Health
  /// is unavailable.
  Future<bool> requestAuthorization();

  /// Values for the days from [start] up to but not including [end]; none when
  /// [start] is not before [end].
  ///
  /// Throws a [PlatformException] when HealthKit fails the read, rather than
  /// answer as if the days had no data: [healthDatabaseInaccessible] while the
  /// device is locked (try again once it is unlocked), [healthNotDetermined]
  /// before [requestAuthorization] has shown the sheet, and `query-failed`
  /// otherwise.
  Future<HealthRead> dailyValues(
    Set<HealthMetric> metrics,
    DateTime start,
    DateTime end,
  );

  /// One page of [metric]'s samples that start from [start] up to but not
  /// including [end], at most [limit] of them (capped at
  /// [maxHealthSamplesPerCall]). Page through a long window with
  /// [healthSamplePages]. Throws as [dailyValues] does.
  Future<HealthSampleRead> samples(
    HealthSampleMetric metric,
    DateTime start,
    DateTime end, {
    int limit = maxHealthSamplesPerCall,
  });
}

/// HealthChannel.swift's cap on one call, so a year of minute-level heart
/// rate is read in pages rather than held in one answer.
const int maxHealthSamplesPerCall = 20000;

/// Every page of [metric] from [start] to [end], oldest first, each read once
/// the previous one is handled. A single [HealthUnavailable] when Health is
/// unavailable. Throws a [StateError] rather than loop if a page's next start
/// does not move forward; a provider that reads this must catch it, as it
/// must every failure here, so that it never reaches a crash report.
Stream<HealthSampleRead> healthSamplePages(
  HealthSource source,
  HealthSampleMetric metric,
  DateTime start,
  DateTime end, {
  int limit = maxHealthSamplesPerCall,
}) async* {
  DateTime from = start;
  while (from.isBefore(end)) {
    final HealthSampleRead read = await source.samples(
      metric,
      from,
      end,
      limit: limit,
    );
    yield read;
    switch (read) {
      case HealthUnavailable():
        return;
      case HealthSamples(next: null):
        return;
      case HealthSamples(next: final DateTime next):
        if (!next.isAfter(from)) {
          throw StateError('Health sample page did not move forward');
        }
        from = next;
    }
  }
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
  Future<HealthRequestStatus> requestStatus() async {
    if (!_supported) return HealthRequestStatus.unknown;
    final String? status;
    try {
      status = await _channel.invokeMethod<String>('requestStatus');
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return HealthRequestStatus.unknown;
      rethrow;
    } on MissingPluginException {
      return HealthRequestStatus.unknown;
    }
    return switch (status) {
      'shouldRequest' => HealthRequestStatus.shouldRequest,
      'unnecessary' => HealthRequestStatus.unnecessary,
      _ => HealthRequestStatus.unknown,
    };
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
    if (!start.isBefore(end)) return const HealthValues([]);
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

  @override
  Future<HealthSampleRead> samples(
    HealthSampleMetric metric,
    DateTime start,
    DateTime end, {
    int limit = maxHealthSamplesPerCall,
  }) async {
    if (!_supported) return const HealthUnavailable();
    if (!start.isBefore(end)) return const HealthSamples([]);
    final Object? page;
    try {
      page = await _channel.invokeMethod<Object?>('samples', {
        'metric': metric.id,
        'start': start.microsecondsSinceEpoch,
        'end': end.microsecondsSinceEpoch,
        'limit': limit.clamp(1, maxHealthSamplesPerCall),
      });
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') return const HealthUnavailable();
      rethrow;
    } on MissingPluginException {
      return const HealthUnavailable();
    }
    return decodeHealthSamplePage(page);
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

/// Reads `{samples: [start, end, value, ...], next}`, times in microseconds
/// since 1970. Drops any triple that is not finite or ends before it starts.
@visibleForTesting
HealthSamples decodeHealthSamplePage(Object? page) {
  if (page is! Map) return const HealthSamples([]);
  final Object? flat = page['samples'];
  final List<HealthSample> samples = <HealthSample>[];
  if (flat is List<double>) {
    for (int i = 0; i + 2 < flat.length; i += 3) {
      final double start = flat[i], end = flat[i + 1], value = flat[i + 2];
      if (!start.isFinite || !end.isFinite || !value.isFinite) continue;
      if (end < start) continue;
      samples.add(
        HealthSample(
          DateTime.fromMicrosecondsSinceEpoch(start.toInt()),
          DateTime.fromMicrosecondsSinceEpoch(end.toInt()),
          value,
        ),
      );
    }
  }
  final Object? next = page['next'];
  return HealthSamples(
    samples,
    next: next is int ? DateTime.fromMicrosecondsSinceEpoch(next) : null,
  );
}
