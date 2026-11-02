# The three activity-removal paths differ in confirmation, feedback and in-flight state

**Severity:** medium

The record dialog's Undo deletes from a snackbar closure with no confirmation and no feedback that it succeeded, and the closure outlives the dialog `State` that created it. The history page's trash icon deletes immediately with no confirmation and no undo, showing a deleted-confirmation snackbar after the fact.

The editor's delete acts immediately and pops the page, and unlike its own save path it never sets the loading flag, so the button stays live during the round trip. A user who mis-taps the history row's icon has no recovery route in the app.

## Evidence

- `lib/vice_activity_history_page.dart:83` — `onPressed: () async {\n                            try {\n                              await FirebaseFirestore.instance\n                                  .collection('activities')\n                                  .doc(activity.id)\n                                  .delete();`
- `lib/vice_activity_editor_page.dart:70` — `Future<void> _deleteActivity() async {\n    try {\n      await FirebaseFirestore.instance`
- `lib/widgets/record_new_activity_dialog.dart:285` — `action: SnackBarAction(\n                        label: 'Undo',\n                        onPressed: () async {`
