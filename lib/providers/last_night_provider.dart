import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/providers/insights_provider.dart';
import 'package:tracker/providers/today_provider.dart';

// Health values stay on the device, and every provider failure goes to
// Crashlytics, so nothing here may fail: each read's failure is a null.

/// Last night against the person's usual, for Today's line and the top of
/// Insights; null where Health is not connected or cannot be read. Read once
/// per day while watched; when Health has no sleeping heart rate for last
/// night yet (the Watch may not have synced), read again on the next resume.
final lastNightProvider = FutureProvider.autoDispose<LastNight?>((ref) async {
  if (defaultTargetPlatform == TargetPlatform.macOS) return null;
  final DateTime today = ref.watch(todayProvider);
  final HealthSource source = ref.watch(healthSourceProvider);
  final Future<bool> connected = ref.watch(healthConnectedProvider.future);
  final LastNight? night = await _read(ref, source, connected, today);
  if (ref.mounted && night?.sleepingHeartRate == null) {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: ref.invalidateSelf,
    );
    ref.onDispose(lifecycle.dispose);
  }
  return night;
});

Future<LastNight?> _read(
  Ref ref,
  HealthSource source,
  Future<bool> connected,
  DateTime today,
) async {
  final DateTime first = addDays(today, -lastNightBaselineNights);
  try {
    if (!await connected || !await source.isAvailable()) return null;
  } catch (_) {
    return null;
  }
  // One read per measure: someone who connected before heart rate was read
  // gets not-determined for it, which must not cost them the sleep row.
  Future<Map<DateTime, double>> nights(HealthMetric metric) async {
    try {
      final HealthRead read = await source.dailyValues(
        <HealthMetric>{metric},
        first,
        addDays(today, 1),
      );
      if (read is! HealthValues) return const <DateTime, double>{};
      return <DateTime, double>{
        for (final DailyOutcome v in read.values)
          if (v.metricId == metric.id) v.date: v.value,
      };
    } catch (_) {
      return const <DateTime, double>{};
    }
  }

  final Map<DateTime, double> asleep = await nights(HealthMetric.sleepAsleep);
  if (!ref.mounted) return null;
  final Map<DateTime, double> heart = await nights(
    HealthMetric.sleepingHeartRate,
  );
  if (!ref.mounted) return null;
  final LastNight night = LastNight(
    sleepingHeartRate: compareLastNight(heart, today),
    heartRateVariability: compareLastNight(
      await _hrvInBed(ref, source, addDays(first, -1)),
      today,
    ),
    asleep: compareLastNight(asleep, today),
  );
  return night.isEmpty ? null : night;
}

// HRV is stored per day, waking hours included, so a night's comes from the
// readings taken in bed. Empty when either read fails.
Future<Map<DateTime, double>> _hrvInBed(
  Ref ref,
  HealthSource source,
  DateTime from,
) async {
  final DateTime now = clock.now();
  Future<List<HealthSample>?> read(HealthSampleMetric metric) async {
    final List<HealthSample> got = <HealthSample>[];
    await for (final HealthSampleRead page in healthSamplePages(
      source,
      metric,
      from,
      now,
    )) {
      if (!ref.mounted) return null;
      switch (page) {
        case HealthUnavailable():
          return null;
        case HealthSamples(:final List<HealthSample> samples):
          got.addAll(samples);
      }
    }
    return got;
  }

  try {
    final List<HealthSample>? bed = await read(HealthSampleMetric.bed);
    if (bed == null || bed.isEmpty) return const <DateTime, double>{};
    final List<HealthSample>? hrv = await read(
      HealthSampleMetric.heartRateVariabilitySDNN,
    );
    if (hrv == null) return const <DateTime, double>{};
    return meansInBed(bed, hrv);
  } catch (_) {
    return const <DateTime, double>{};
  }
}

/// Whether it is before local noon, when Today shows last night's line. Moves
/// at noon and midnight; iOS suspends timers in the background, so a resume
/// recomputes it too.
final morningProvider = NotifierProvider<Morning, bool>(Morning.new);

class Morning extends Notifier<bool> {
  Timer? _next;

  @override
  bool build() {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: _refresh,
    );
    ref.onDispose(() {
      _next?.cancel();
      lifecycle.dispose();
    });
    return _arm();
  }

  bool _arm() {
    final DateTime now = clock.now();
    final DateTime noon = DateTime(now.year, now.month, now.day, 12);
    final bool morning = now.isBefore(noon);
    _next?.cancel();
    _next = Timer(
      (morning ? noon : addDays(startOfDay(now), 1)).difference(now),
      _refresh,
    );
    return morning;
  }

  void _refresh() {
    state = _arm();
  }
}
