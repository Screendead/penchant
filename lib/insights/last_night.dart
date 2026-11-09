import 'package:tracker/data/day.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights/stats.dart';

/// The nights before last night that make "your usual".
const int lastNightBaselineNights = 28;

/// The fewest of those nights with a value for a usual to be given.
const int lastNightMinBaseline = 14;

enum NightSide { below, usual, above }

/// Last night's value of one measure against the nights before it.
class NightCompare {
  const NightCompare({
    required this.value,
    required this.usual,
    required this.low,
    required this.high,
  });

  /// Last night's value.
  final double value;

  /// The median of the baseline nights.
  final double usual;

  /// The baseline's 10th and 90th percentiles ([quantile]): the usual range.
  final double low;
  final double high;

  /// The value, the usual and their difference as whole numbers, so a row
  /// reading "57 bpm · usual 54 · 3 above" adds up.
  int get shownValue => value.round();
  int get shownUsual => usual.round();
  int get shownBy => (shownValue - shownUsual).abs();

  /// Above or below the usual range, on the whole numbers shown, so a night
  /// is never "0 above" and a value shown at the range's edge is inside it.
  NightSide get side {
    if (shownBy == 0) return NightSide.usual;
    if (shownValue > high.round()) return NightSide.above;
    if (shownValue < low.round()) return NightSide.below;
    return NightSide.usual;
  }
}

/// [byNight]'s value for [today]'s night against the
/// [lastNightBaselineNights] before it; null without a value for last night
/// or with under [lastNightMinBaseline] nights before it.
NightCompare? compareLastNight(Map<DateTime, double> byNight, DateTime today) {
  final double? last = byNight[today];
  if (last == null) return null;
  final List<double> before = <double>[
    for (int back = 1; back <= lastNightBaselineNights; back++)
      if (byNight[addDays(today, -back)] case final double v) v,
  ];
  if (before.length < lastNightMinBaseline) return null;
  return NightCompare(
    value: last,
    usual: quantile(before, 0.5),
    low: quantile(before, 0.1),
    high: quantile(before, 0.9),
  );
}

/// The night a sleep ending at [end] belongs to, as [DailyOutcome.date] keys
/// it: a sleep ending between noon on D-1 and noon on D is night D.
DateTime nightOf(DateTime end) =>
    end.hour < 12 ? startOfDay(end) : addDays(startOfDay(end), 1);

/// The mean of [readings] inside [bed] spans, by night. A reading is inside
/// when its midpoint is; a night with no reading inside has no value.
Map<DateTime, double> meansInBed(
  List<HealthSample> bed,
  List<HealthSample> readings,
) {
  final Map<DateTime, (double, int)> sums = <DateTime, (double, int)>{};
  for (final HealthSample r in readings) {
    final DateTime mid = r.start.add(r.end.difference(r.start) ~/ 2);
    for (final HealthSample span in bed) {
      if (mid.isBefore(span.start) || mid.isAfter(span.end)) continue;
      final DateTime night = nightOf(span.end);
      final (double sum, int n) = sums[night] ?? (0, 0);
      sums[night] = (sum + r.value, n + 1);
      break;
    }
  }
  return <DateTime, double>{
    for (final MapEntry<DateTime, (double, int)> e in sums.entries)
      e.key: e.value.$1 / e.value.$2,
  };
}

/// Last night's sleeping heart rate, HRV and time asleep, each against the
/// nights before it; a measure Health lacks for last night, or for too many
/// nights before it, is null.
class LastNight {
  const LastNight({
    this.sleepingHeartRate,
    this.heartRateVariability,
    this.asleep,
  });

  /// Beats per minute.
  final NightCompare? sleepingHeartRate;

  /// SDNN in milliseconds, from readings taken in bed.
  final NightCompare? heartRateVariability;

  /// Minutes.
  final NightCompare? asleep;

  bool get isEmpty =>
      sleepingHeartRate == null &&
      heartRateVariability == null &&
      asleep == null;
}
