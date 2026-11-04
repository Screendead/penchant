# Two files are outside the format check

**Severity:** low

CI runs `dart format --set-exit-if-changed` over `lib`, `test` and `integration_test`, except `lib/widgets/record_new_activity_dialog.dart` (not yet formatted) and `lib/vice_activity_editor_page.dart`. Its ternary-branched lock icons and `Timer.periodic` duration omit `const` where the editor page marks them `const`.

## Evidence

- `.github/workflows/checks.yml` — the `Format` step's `! -path` exclusions
- `lib/widgets/record_new_activity_dialog.dart:77` — `dateUpdaterTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {`
