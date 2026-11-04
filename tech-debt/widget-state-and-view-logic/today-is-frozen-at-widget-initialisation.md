# App left open past midnight keeps showing yesterday as today

**Severity:** medium

`_UsageGraphViewState` derives `today` in `initState` as a `late final` field, and the graph's `IndexedStack` keeps it mounted for the whole session. A session left open across midnight keeps the graph's range ending on the previous day, so a newly recorded activity falls outside the window on screen.

The Today tab shows `selectedDay`, which `_ViceTrackerState` sets once, when the state is created. Its `build` recomputes `today` only to clamp `selectedDay` into the range from `oldestDay` to `today`, so a rebuild after midnight never moves the selection forward: a tab left on Today relabels itself "Yesterday" and keeps showing yesterday's totals until the user taps Today. Nothing triggers a rebuild at midnight and nothing listens for the app resuming, which is the normal case for a mobile tracker brought back from the background.

## Evidence

- `lib/usage_graph_view.dart:79` — `today = startOfDay(DateTime.now());` (in `initState`)
- `lib/usage_graph_view.dart:62` — `late final DateTime today;`
- `lib/vice_tracker.dart:20` — `DateTime selectedDay = startOfDay(DateTime.now());`
- `lib/vice_tracker.dart:37` — `final DateTime day = selectedDay.isAfter(today)\n        ? today\n        : selectedDay.isBefore(oldestDay)\n        ? oldestDay\n        : selectedDay;` (inside `build`; only clamps)
- `lib/homepage.dart:66` — `child: IndexedStack(\n              index: selectedTabIndex,`
- **`grep -rn "WidgetsBindingObserver\|AppLifecycle" lib/`** → only `lib/account_settings.dart`, for a profile reload
