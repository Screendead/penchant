# Long lines, a misindented block, missing const, and a stripped trailing newline

**Severity:** low

Fourteen lines across five files exceed the 80-column width `dart format` wraps to, worst at 127 and 114 characters, and `record_new_activity_dialog.dart` has a visibly misindented map literal followed by a timeout call. That file's ternary-branched lock icons and its `Timer.periodic` duration omit `const` while the structurally identical code in the editor page marks the equivalents `const`.

`vice_tracker.dart` lost its final newline in the rewrite, which git reports explicitly, so every future diff touching its last line shows a spurious removal and re-addition of the closing brace. No CI step runs `dart format` or `flutter analyze` to surface any of it.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:127` — `icon: manualDate\n                          ? Icon(Icons.lock_open)\n                          : Icon(Icons.lock_clock),`
- `lib/vice_activity_editor_page.dart:205` — `icon: manualDate\n                            ? const Icon(Icons.lock_open)\n                            : const Icon(Icons.lock_clock),`
- `lib/widgets/record_new_activity_dialog.dart:48` — `dateUpdaterTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {`
- `lib/widgets/record_new_activity_dialog.dart:251` — `await activityRef.set({\n                      'createdAt': date,`
- `lib/vice_activity_history_page.dart:60` — `'${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',`
- **`git diff lib/vice_tracker.dart`** → `-}\n+}\n\ No newline at end of file`
