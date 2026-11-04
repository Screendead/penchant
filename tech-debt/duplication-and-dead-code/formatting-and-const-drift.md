# Long lines, missing const, and a format check nothing runs

**Severity:** low

Five hand-written lines across three files exceed the 80-column width `dart format` wraps to, worst at 125 characters, and `lib/errors/not_found.dart` is not formatted as `dart format` would write it. `record_new_activity_dialog.dart`'s ternary-branched lock icons and its `Timer.periodic` duration omit `const` while the structurally identical code in the editor page marks the equivalents `const`.

No CI step runs `dart format`, so drift like this surfaces only when someone formats by hand. `flutter analyze` runs, but the template lint set does not flag any of it.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:248` — `icon: manualDate\n                              ? Icon(Icons.lock_open)\n                              : Icon(Icons.lock_clock),`
- `lib/vice_activity_editor_page.dart:240` — `icon: manualDate\n                            ? const Icon(Icons.lock_open)\n                            : const Icon(Icons.lock_clock),`
- `lib/widgets/record_new_activity_dialog.dart:74` — `dateUpdaterTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {`
- `lib/vice_activity_history_page.dart:139` — `'${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',`
- **`dart format --output=none --set-exit-if-changed lib test integration_test`** → `Changed lib/errors/not_found.dart`, exit 1
- **`grep -rn "dart format" .github tools`** → (no output)
