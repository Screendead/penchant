# The last weekly bucket covers only the remainder of the range and is summed, not averaged

**Severity:** medium

The bucket count is computed from an integer division of the range by the step, and activities are placed by integer division of their day offset, so the final bucket spans whatever is left over. At the default 30-day range in Weekly mode there are five buckets, four of seven days and one of two, and totals are summed per bucket rather than averaged.

The rightmost point of the line, the one showing current behaviour, is depressed by construction and the moving average inherits the dip; the same applies to the 90, 180 and 365-day ranges.

## Evidence

- `lib/usage_graph_view.dart:138` — `final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;`
- `lib/usage_graph_view.dart:148` — `final int bucketIndex = deltaDays ~/ stepDays;\n        if (bucketIndex >= 0 && bucketIndex < totals.length) {\n          totals[bucketIndex] += activity.quantity.toDouble();`
