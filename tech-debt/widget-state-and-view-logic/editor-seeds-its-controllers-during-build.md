# The activity editor writes to TextEditingControllers from inside build behind a one-shot flag

**Severity:** medium

`build` calls `initializeFromActivity` after its loading guards, and that method assigns to `dateController.text` and `quantityController.text`, which notifies listeners during the build pass of the tree listening to them. An initialized flag makes it fire only on the first successful build, so a Firestore change to the activity while the editor is open is never reflected in the fields, and a concurrent edit is overwritten by the stale values on save.

## Evidence

- `lib/vice_activity_editor_page.dart:154` — `viceActivityProvider(widget.activityID),`
- `lib/vice_activity_editor_page.dart:168` — `final ViceActivity? activity = activityValue.value;`
- `lib/vice_activity_editor_page.dart:178` — `initializeFromActivity(activity);`
- `lib/vice_activity_editor_page.dart:41` — `void initializeFromActivity(ViceActivity activity) {\n    if (initialized) {\n      return;\n    }\n\n    dateController.text = dateFormat.format(activity.createdAt.toDate());`
