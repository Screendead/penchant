# One Flutter test that asserts its own literal, plus two empty Xcode test stubs

**Severity:** high

`test/widget_test.dart` pumps a hand-built `MaterialApp` holding a `Text` widget and asserts that text renders; it never constructs the app's own root widget, touches Firebase or Riverpod, or exercises any real widget. There is no coverage anywhere for model serialization, for any of the providers including their empty-stream branches and `whereIn` construction, for any form, validator or dialog, or as goldens.

The iOS and macOS RunnerTests files are both the unmodified template, a single example method containing only comments, wired into their schemes' test action and reporting a pass with zero coverage.

## Evidence

- `test/widget_test.dart:7` — `const MaterialApp(\n        home: Scaffold(\n          body: Text('Tracker smoke test'),\n        ),\n      ),`
- `test/widget_test.dart:14` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- `ios/RunnerTests/RunnerTests.swift:6` — `func testExample() {\n    // If you add code to the Runner application, consider adding tests here.\n    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.\n  }`
- `macos/RunnerTests/RunnerTests.swift:6` — `func testExample() {\n    // If you add code to the Runner application, consider adding tests here.\n    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.\n  }`
