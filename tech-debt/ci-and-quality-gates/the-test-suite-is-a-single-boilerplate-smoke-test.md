# No unit or widget tests: one boilerplate Flutter test, two empty Xcode stubs, one end-to-end path

**Severity:** high

`test/widget_test.dart` pumps a hand-built `MaterialApp` holding a `Text` widget and asserts that text renders; it never constructs the app's own root widget, touches Firebase or Riverpod, or exercises any real widget. Nothing unit-tests model serialization or any provider, including their empty-stream branches and `whereIn` construction. There are no widget tests of a form, validator or dialog, and no goldens.

The only real coverage is `integration_test/smoke_test.dart`, one happy path (register, add vices, record an activity, see it in Manage Data). It needs a simulator and the emulators, takes minutes, and CI does not run it. Archiving, editing, deleting, sign-in, validation errors and date navigation have no test at any level.

The iOS and macOS RunnerTests files are both the unmodified template, a single example method containing only comments, wired into their schemes' test action and reporting a pass with zero coverage.

## Evidence

- `test/widget_test.dart:7` — `const MaterialApp(\n        home: Scaffold(\n          body: Text('Tracker smoke test'),\n        ),\n      ),`
- `test/widget_test.dart:14` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- **`ls integration_test/`** → `smoke_test.dart`
- `ios/RunnerTests/RunnerTests.swift:6` — `func testExample() {\n    // If you add code to the Runner application, consider adding tests here.\n    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.\n  }`
- `macos/RunnerTests/RunnerTests.swift:6` — `func testExample() {\n    // If you add code to the Runner application, consider adding tests here.\n    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.\n  }`
