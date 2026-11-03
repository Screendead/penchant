# The IndexedStack keeps both tabs built, so both chart pipelines run at once

**Severity:** low

Homepage's body, under the offline banner, is an `IndexedStack`, which builds and retains both children regardless of the selected index. `UsageGraphView.initState` runs at app start and its graph provider opens a Firestore listener for the default vice and 30-day range before the tab is ever visited, alongside the Today tab's day listener.

Both listeners stay subscribed whichever tab is visible, and both pipelines recompute on rebuild.

## Evidence

- `lib/homepage.dart:66` — `child: IndexedStack(\n              index: selectedTabIndex,`
- `lib/homepage.dart:68` — `children: const [ViceTracker(), UsageGraphView()],`
- `lib/usage_graph_view.dart:68` — `void initState() {`
