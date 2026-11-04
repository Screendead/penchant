# smoothingWindow is clamped in three inconsistent places and applied unclamped

**Severity:** medium

The timestep dropdown's `onChanged` clamps the value against a bucket count captured from the build that created the dropdown, so switching from Daily to Weekly at a 30-day range clamps against 30 buckets when the new count is 5. `_applyRange` does not clamp at all, and the Slider clamps only its displayed value while the header caption and the moving-average call both read the raw field.

The result is a slider sitting at its maximum, a caption showing a larger number, and an average computed over a window wider than the data has buckets.

## Evidence

- `lib/usage_graph_view.dart:110` — `Widget build(BuildContext context) {`
- `lib/usage_graph_view.dart:138` — `final int bucketCount = ((rangeDays - 1) ~/ stepDays) + 1;`
- `lib/usage_graph_view.dart:155` — `final List<double> smoothed = _movingAverage(totals, smoothingWindow);`
- `lib/usage_graph_view.dart:249` — `smoothingWindow = min(smoothingWindow, bucketCount);`
- `lib/usage_graph_view.dart:285` — `'Smoothing: $smoothingWindow buckets for ${selectedVice.name}',`
- `lib/usage_graph_view.dart:296` — `value: smoothingWindow.clamp(1, smoothingMaxBuckets).toDouble(),`
