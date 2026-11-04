import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';

// The most buckets the moving average may span.
const int maxSmoothingWindow = 7;

// The days the usage graph covers: [bucketCount] buckets of [stepDays] days
// each, the first starting at [start] and the last ending with today.
typedef UsageRange = ({DateTime start, int stepDays, int bucketCount});

// A weekly range covers only whole weeks, so a 30-day range shows 4 weeks
// (28 days): every bucket is a full [stepDays] long and is comparable with
// the others, including the newest.
UsageRange usageRange(DateTime today, int rangeDays, int stepDays) {
  final int bucketCount = max(1, rangeDays ~/ stepDays);
  return (
    start: addDays(startOfDay(today), 1 - bucketCount * stepDays),
    stepDays: stepDays,
    bucketCount: bucketCount,
  );
}

extension UsageRangeDays on UsageRange {
  int get days => bucketCount * stepDays;

  // Exclusive: midnight after the last day.
  DateTime get end => addDays(start, days);

  DateTime bucketStart(int index) => addDays(start, index * stepDays);
}

// The total quantity recorded in each bucket of [range]. Activities outside
// the range are ignored.
List<double> bucketTotals(UsageRange range, Iterable<ViceActivity> activities) {
  final List<double> totals = List<double>.filled(range.bucketCount, 0);

  for (final ViceActivity activity in activities) {
    final int offset = daysBetween(range.start, activity.createdAt.toDate());
    // `~/` truncates toward zero, so a day before the range would land in 0.
    if (offset < 0) {
      continue;
    }
    final int index = offset ~/ range.stepDays;
    if (index < totals.length) {
      totals[index] += activity.quantity;
    }
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
