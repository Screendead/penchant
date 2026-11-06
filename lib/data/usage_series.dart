import 'dart:math';

import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice_activity.dart';

// The most buckets the moving average may span.
const int maxSmoothingWindow = 30;

// The window the average starts at: a week of days, or four weeks.
int defaultWindow(int stepDays) => stepDays == 1 ? 7 : 4;

// The [days] days the Trends chart covers, from [start] to the end of today,
// in buckets of [stepDays] days.
typedef UsageRange = ({DateTime start, int days, int stepDays});

// [rangeDays] rounded down to whole buckets (a 30-day weekly range covers 28),
// so no bucket is short (Jack, 2026-11-06).
UsageRange usageRange(DateTime today, int rangeDays, int stepDays) {
  final int days = max(stepDays, rangeDays ~/ stepDays * stepDays);
  return (
    start: addDays(startOfDay(today), 1 - days),
    days: days,
    stepDays: stepDays,
  );
}

extension UsageRangeDays on UsageRange {
  int get bucketCount => days ~/ stepDays;

  // Exclusive: midnight after the last day.
  DateTime get end => addDays(start, days);

  DateTime bucketStart(int index) => addDays(start, index * stepDays);
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

typedef UsageStats = ({double total, double average, int peakIndex});

// The range's total, its average per day (daily) or per week (weekly), and
// the first bucket holding the most.
UsageStats usageStats(UsageRange range, List<double> totals) {
  double total = 0;
  int peakIndex = 0;
  for (int i = 0; i < totals.length; i++) {
    total += totals[i];
    if (totals[i] > totals[peakIndex]) {
      peakIndex = i;
    }
  }
  final int per = range.stepDays == 1 ? range.days : totals.length;
  return (
    total: total,
    average: per == 0 ? 0 : total / per,
    peakIndex: peakIndex,
  );
}

// The most days the hour-of-day profile looks back over.
const int hourProfileMaxDays = 90;

typedef HourProfile = ({
  // The quantity logged in each local hour, 0 to 23.
  List<double> hours,
  double total,
  // The first hour of the three in a row, wrapping past midnight, that hold
  // the most; the earliest on a tie.
  int busiestStart,
  // The share logged before noon, rounded to a whole percent.
  int beforeNoonPercent,
});

// The last [hourProfileMaxDays] days of [range], or all of a shorter one.
DateTime hourProfileStart(UsageRange range) =>
    addDays(range.end, -min(range.days, hourProfileMaxDays));

// When in the day [activities] happen, counting those from [start] to the
// end of [range].
HourProfile hourProfile(UsageRange range, Iterable<ViceActivity> activities) {
  final DateTime start = hourProfileStart(range);
  final DateTime end = range.end;
  final List<double> hours = List<double>.filled(24, 0);
  for (final ViceActivity activity in activities) {
    final DateTime at = activity.createdAt.toDate();
    if (at.isBefore(start) || !at.isBefore(end)) {
      continue;
    }
    hours[at.hour] += activity.quantity;
  }

  int busiestStart = 0;
  double busiest = -1;
  for (int h = 0; h < 24; h++) {
    final double sum = hours[h] + hours[(h + 1) % 24] + hours[(h + 2) % 24];
    if (sum > busiest) {
      busiest = sum;
      busiestStart = h;
    }
  }
  final double total = hours.fold<double>(0, (double a, double b) => a + b);
  final double morning = hours
      .sublist(0, 12)
      .fold<double>(0, (double a, double b) => a + b);
  return (
    hours: hours,
    total: total,
    busiestStart: busiestStart,
    beforeNoonPercent: total == 0 ? 0 : (morning / total * 100).round(),
  );
}
