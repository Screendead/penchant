# Two template tests still run and check nothing about the app

**Severity:** low

`test/` and `integration_test/` cover the app, the usage graph's arithmetic included. Two tests left from the
project templates remain: `test/widget_test.dart` pumps a hardcoded string and finds it, and the iOS `RunnerTests` is
the unmodified Xcode template, wired into its scheme's test action and passing with zero coverage. Each reads as
coverage that is not there. (The macOS `RunnerTests` now test the window's opening size.)

## Evidence

- `test/widget_test.dart:10` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- `ios/RunnerTests/RunnerTests.swift:7` — `func testExample() {`
