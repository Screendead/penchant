# Both date-driven views capture today once and never recompute it

**Severity:** medium

`_ViceTrackerState` computes `now` as a field initializer and derives `today` in `initState`, and `_UsageGraphViewState` does the same; neither recomputes, and both live in an `IndexedStack` that keeps them mounted for the whole session. A session left open across midnight keeps showing the previous day's Today label, its 30-entry date dropdown and the graph's range end, and newly recorded activities fall outside the day window on screen.

Nothing recomputes either value on resume, which is the normal case for a mobile tracker brought back from the background.

## Evidence

- `lib/vice_tracker.dart:15` — `final DateTime now = DateTime.now();`
- `lib/vice_tracker.dart:31` — `today = DateTime(now.year, now.month, now.day);`
- `lib/usage_graph_view.dart:28` — `void initState() {\n    super.initState();\n    final DateTime now = DateTime.now();\n    today = DateTime(now.year, now.month, now.day);\n  }`
- `lib/homepage.dart:63` — `body: IndexedStack(\n        index: selectedTabIndex,\n        children: const [\n          ViceTracker(),\n          UsageGraphView(),\n        ],\n      ),`
