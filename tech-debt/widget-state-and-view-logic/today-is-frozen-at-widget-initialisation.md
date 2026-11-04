# The Graph tab captures today once and never recomputes it

**Severity:** medium

`_UsageGraphViewState` derives `today` in `initState` as a `late final` field, and the graph's `IndexedStack` keeps it mounted for the whole session. A session left open across midnight keeps the graph's range ending on the previous day, so a newly recorded activity falls outside the window on screen.

The Today tab recomputes its `today` inside `build`, so it moves on at the next rebuild, but nothing triggers a rebuild at midnight and nothing listens for the app resuming, which is the normal case for a mobile tracker brought back from the background. Until something else rebuilds it, the Today tab keeps showing the previous day too.

## Evidence

- `lib/usage_graph_view.dart:68` — `void initState() {\n    super.initState();\n    final DateTime now = DateTime.now();\n    today = DateTime(now.year, now.month, now.day);\n  }`
- `lib/usage_graph_view.dart:61` — `late final DateTime today;`
- `lib/vice_tracker.dart:30` — `final DateTime today = startOfDay(DateTime.now());` (inside `build`)
- `lib/homepage.dart:66` — `child: IndexedStack(\n              index: selectedTabIndex,`
- **`grep -rn "WidgetsBindingObserver\|AppLifecycle" lib/`** → only `lib/account_settings.dart`, for a profile reload
