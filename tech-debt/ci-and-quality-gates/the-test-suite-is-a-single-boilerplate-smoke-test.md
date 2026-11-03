# Auth, archiving and the usage graph have no tests, and CI never runs the end-to-end suite

**Severity:** medium

`test/` covers the day and list activity providers, calendar arithmetic, the Today tab, the form validators and the model parsers. `integration_test/` drives the real app against the emulators: registering, adding vices, recording, day navigation, record Undo, and deleting from the history page and editor. Nothing tests sign-in and its error paths, archiving and unarchiving, saving an edit, or the usage graph's bucketing. There are no goldens.

The end-to-end suite needs an iOS Simulator and takes minutes; CI does not run it, so it guards only the runs someone starts by hand. `test/widget_test.dart` is still the template check of a hardcoded string, and the iOS and macOS RunnerTests files are still the unmodified template, wired into their schemes' test action and passing with zero coverage.

## Evidence

- **`ls test/ integration_test/`** → `activity_providers_test.dart day_test.dart fakes.dart form_validation_test.dart model_parsing_test.dart vice_tracker_test.dart widget_test.dart`; `activity_flows_test.dart smoke_test.dart support.dart`
- `test/widget_test.dart:14` — `expect(find.text('Tracker smoke test'), findsOneWidget);`
- **`grep -rn integration_test .github/`** → no matches
- `ios/RunnerTests/RunnerTests.swift:6` — `func testExample() {`
