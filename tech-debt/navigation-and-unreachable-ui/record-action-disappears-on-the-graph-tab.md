# Homepage empties the AppBar actions whenever the selected tab is not Today

**Severity:** low

Homepage rebuilds its `AppBar` actions from the selected index and supplies an empty list for any tab other than Today. The Record button was previously present on the app's only screen, so with the tab bar it disappears while the user is looking at the graph, and recording an activity requires switching tabs first.

## Evidence

- `lib/homepage.dart:23` — `actions: selectedTabIndex == 0\n            ? const <Widget>[\n                RecordNewActivityButton(),\n              ]\n            : const <Widget>[],`
- `lib/homepage.dart:63` — `body: IndexedStack(\n        index: selectedTabIndex,`
