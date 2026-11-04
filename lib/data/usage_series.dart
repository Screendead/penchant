import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';

// The most buckets the moving average may span.
const int maxSmoothingWindow = 7;

// The [days] days the usage graph covers, from [start] to the end of today,
// in buckets of [stepDays] days.
typedef UsageRange = ({DateTime start, int days, int stepDays});

UsageRange usageRange(DateTime today, int rangeDays, int stepDays) => (
  start: addDays(startOfDay(today), 1 - rangeDays),
  days: rangeDays,
  stepDays: stepDays,
);

// Buckets are counted back from today, so the newest is always a whole
// [stepDays] long; when [days] is not a multiple of [stepDays], the oldest
// bucket holds the remainder (2 days of a 30-day weekly range).
extension UsageRangeDays on UsageRange {
  int get bucketCount => max(1, (days + stepDays - 1) ~/ stepDays);

  // Exclusive: midnight after the last day.
  DateTime get end => addDays(start, days);

  DateTime bucketStart(int index) =>
      addDays(start, max(0, days - (bucketCount - index) * stepDays));
}

// The total quantity recorded in each bucket of [range]. Activities outside
// the range are ignored.
List<double> bucketTotals(UsageRange range, Iterable<ViceActivity> activities) {
  final int bucketCount = range.bucketCount;
  final List<double> totals = List<double>.filled(bucketCount, 0);

  for (final ViceActivity activity in activities) {
    final int offset = daysBetween(range.start, activity.createdAt.toDate());
    if (offset < 0 || offset >= range.days) {
      continue;
    }
    final int daysAgo = range.days - 1 - offset;
    totals[bucketCount - 1 - daysAgo ~/ range.stepDays] += activity.quantity;
  }

  return totals;
}

// The widest window the smoothing control offers for [bucketCount] buckets.
int smoothingLimit(int bucketCount) =>
    max(1, min(maxSmoothingWindow, bucketCount));

// The window actually applied, shown and announced: the one picked, within
// what [bucketCount] buckets allow.
int effectiveWindow(int picked, int bucketCount) =>
    picked.clamp(1, smoothingLimit(bucketCount));

// The trailing average over [window] buckets; the first buckets, with fewer
// before them, average over what there is.
List<double> movingAverage(List<double> values, int window) {
  final int span = window.clamp(1, max(1, values.length));
  if (span == 1) {
    return List<double>.of(values);
  }

  final List<double> averages = List<double>.filled(values.length, 0);
  double sum = 0;
  for (int i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= span) {
      sum -= values[i - span];
    }
    averages[i] = sum / min(i + 1, span);
  }
  return averages;
}
