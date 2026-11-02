# ViceChart.getTitle calls ref.watch from outside the build phase

**Severity:** medium

fl_chart invokes `getTitle` during layout and paint, and again on every frame of the 600ms radar animation, not during build. flutter_riverpod registers a watch into the element's dependency map, and the next build moves that map aside and closes every subscription the build did not re-watch, so the subscription is torn down and recreated out of phase on every frame. A change to the watched list also invokes `markNeedsBuild` from outside the build phase.

The callback opens a third provider subscription for data the surrounding widget already holds in the `vicesByID` map it builds a few lines above.

## Evidence

- `lib/vice_chart.dart:98` — `getTitle: (int index, double angle) {`
- `lib/vice_chart.dart:99` — `final List<Vice>? vices = ref.watch(viceListProvider).value;`
- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `lib/vice_chart.dart:105` — `final Vice vice = vices.firstWhere(\n              (v) => v.name == todayData.keys.elementAt(index),\n            );`
- **`sed -n '380,442p' ~/.pub-cache/hosted/pub.dev/flutter_riverpod-3.1.0/lib/src/core/consumer.dart`** → `_oldDependencies = _dependencies;\n      for (var i = 0; i < _listeners.length; i++) {\n        _listeners[i].close();`
