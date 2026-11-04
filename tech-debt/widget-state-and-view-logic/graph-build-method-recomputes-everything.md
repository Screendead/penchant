# The whole usage-graph pipeline lives in a 350-line build method

**Severity:** medium

`UsageGraphView.build` computes the date range, allocates the buckets, sums activities into them, runs the moving average, computes the axis maximum and generates both spot lists before returning a tree that inlines three dropdown builders, a slider and a full `LineChartData`. All of it re-runs on every rebuild, including each frame of a slider drag.

The rest of the app's build methods are short and single-purpose by comparison.

## Evidence

- `lib/usage_graph_view.dart:110` — `Widget build(BuildContext context) {`
- `lib/usage_graph_view.dart:138` — `final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;`
- `lib/usage_graph_view.dart:155` — `final List<double> smoothed = _movingAverage(totals, smoothingWindow);`
- `lib/usage_graph_view.dart:249` — `smoothingWindow = min(smoothingWindow, bucketCount);`
- `lib/usage_graph_view.dart:461` — `  }` (the end of `build`, 352 lines after its start)
