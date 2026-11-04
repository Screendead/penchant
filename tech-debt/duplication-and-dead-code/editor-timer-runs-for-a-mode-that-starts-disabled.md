# The activity editor copies the dialog's live-clock timer into a screen that starts in manual mode

**Severity:** low

The editor ticks a one-second `Timer.periodic` that writes the current time into the date controller whenever `manualDate` is false, but initialises `manualDate` to true — the opposite of the dialog — so the timer fires continuously and does nothing unless the user taps the lock icon.

Flipping the lock off and back on re-seeds the field from the activity's stored `createdAt`, so the pattern was carried across without adjusting to the editor's different starting state.

## Evidence

- `lib/vice_activity_editor_page.dart:39` — `bool manualDate = true;`
- `lib/vice_activity_editor_page.dart:66` — `dateUpdaterTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\n      if (mounted && manualDate == false) {\n        dateController.text = nowText;\n      }\n    });`
- `lib/widgets/record_new_activity_dialog.dart:55` — `bool manualDate = false;`
