# The oldest weekly bucket covers only the remainder of the range and is summed, not averaged

**Severity:** low

Weekly buckets are counted back from today, so the newest is always a whole week, and the range covers every day the Trends range segment names. When the range is not a whole number of weeks, the oldest bucket holds what is left: 2 days at 30, 6 at 90, 1 at 365. Totals are summed per bucket, so that leftmost point is lower by construction, and the first points of the moving average inherit the dip, as does the Trends sheet's weekly average, which divides the total by the bucket count, the short one included.

Whether to keep the short bucket as it is, scale it to a weekly rate, or show only whole weeks (and so leave days of the named range off the screen) is a product call that has not been made (`weekly-remainder` in HANDOVER.md).

## Evidence

- `lib/data/usage_series.dart:23-29` — `bucketCount` is `(days + stepDays - 1) ~/ stepDays`, and `bucketStart(0)` is `start`, `days - (bucketCount - 1) * stepDays` days before the second bucket.
- `lib/data/usage_series.dart:34-48` — `bucketTotals` adds each activity's quantity to its bucket with no scaling by the bucket's length.
- `lib/data/usage_series.dart` — `usageStats` divides a weekly range's total by `totals.length`.
