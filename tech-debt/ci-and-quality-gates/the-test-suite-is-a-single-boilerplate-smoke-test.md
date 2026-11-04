# The usage graph's weekly bucketing and smoothing have no tests, and CI never runs the end-to-end suite

**Severity:** medium

`test/` covers the providers, calendar arithmetic, the Today tab, the editor and history pages, accessibility labels, the account flows (sign-in errors, password reset, sign-out, export, deletion), the form validators, the write layer and the model parsers. `integration_test/` drives the real app against the emulators: accounts, adding vices, recording, archiving, editing, deleting, offline writes, navigation and bounded queries. What no test reaches is most of the usage graph's arithmetic: weekly bucketing, the moving average and the axis scale. Only its labels, its daily-total summary and its reserved axis room are checked. There are no goldens.

The end-to-end suite needs an iOS Simulator and takes minutes; CI does not run it (C10: local only), so it guards only the runs someone starts by hand. `test/widget_test.dart` is still the template check of a hardcoded string, and the iOS and macOS RunnerTests files are still the unmodified template, wired into their schemes' test action and passing with zero coverage.

## Evidence

- **`grep -n "UsageGraphView" test/*.dart`** → only `test/accessibility_test.dart`, which checks the series names, one daily-total summary and the axis label room; nothing asserts a weekly bucket or a smoothed value
- `test/widget_test.dart:10` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- **`grep -rn integration_test .github/`** → no matches
- `ios/RunnerTests/RunnerTests.swift:7` — `func testExample() {`
- `macos/RunnerTests/RunnerTests.swift:7` — `func testExample() {`
