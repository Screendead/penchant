# Three template tests still run and check nothing about the app

**Severity:** low

`test/` and `integration_test/` cover the app, the usage graph's arithmetic included. Three tests left from the
project templates remain: `test/widget_test.dart` pumps a hardcoded string and finds it, and the iOS and macOS
`RunnerTests` are the unmodified Xcode template, wired into their schemes' test action and passing with zero coverage.
Each reads as coverage that is not there.

## Evidence

- `test/widget_test.dart:10` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- `ios/RunnerTests/RunnerTests.swift:7` — `func testExample() {`
- `macos/RunnerTests/RunnerTests.swift:7` — `func testExample() {`
