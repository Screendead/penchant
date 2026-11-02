# The whole usage-graph pipeline lives in a 290-line build method

**Severity:** medium

`UsageGraphView.build` computes the date range, allocates the buckets, sums activities into them, runs the moving average, computes the axis maximum and generates both spot lists before returning a tree that inlines three dropdown builders, a slider and a full `LineChartData`. All of it re-runs on every rebuild, including each frame of a slider drag.

The rest of the app's build methods are short and single-purpose by comparison.

## Evidence

- `lib/usage_graph_view.dart:70` — `Widget build(BuildContext context) {`
- `lib/usage_graph_view.dart:104` — `final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;`
- `lib/usage_graph_view.dart:119` — `final List<double> smoothed = _movingAverage(totals, smoothingWindow);`
- `lib/usage_graph_view.dart:205` — `smoothingWindow = min(smoothingWindow, bucketCount);`
- `lib/usage_graph_view.dart:359` — `}`
