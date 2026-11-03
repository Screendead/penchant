# The three activity-removal paths differ in confirmation and recovery

**Severity:** medium

The record dialog's Undo deletes from a snackbar with no confirmation. The history page's trash icon deletes
immediately with no confirmation and no undo, showing a deleted-confirmation snackbar after the fact. The editor's
delete also acts at once and pops the page. A user who mis-taps the history row's icon, or the editor's, has no
recovery route in the app.

## Evidence

- `lib/vice_activity_history_page.dart` — the row's Delete button calls `_delete(activity.id)` directly.
- `lib/vice_activity_editor_page.dart` — the app bar's Delete button calls `_deleteActivity` directly.
- `lib/widgets/record_new_activity_dialog.dart` — `SnackBarAction(label: 'Undo', onPressed: onUndo)`.
