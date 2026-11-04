# The activity editor writes to TextEditingControllers from inside build behind a one-shot flag

**Severity:** medium

`build` calls `initializeFromActivity` after its loading guards, and that method assigns to `dateController.text` and `quantityController.text`, which notifies listeners during the build pass of the tree listening to them. An initialized flag makes it fire only on the first successful build, so a Firestore change to the activity while the editor is open is never reflected in the fields. Save writes only the fields the user changed, so a stale field is no longer written back, but the form can show, and the user can edit from, values the server has since replaced.

## Evidence

- `lib/vice_activity_editor_page.dart:167` — `viceActivityProvider(widget.activityID),`
- `lib/vice_activity_editor_page.dart:184` — `final ViceActivity? activity =`
- `lib/vice_activity_editor_page.dart:194` — `initializeFromActivity(activity);`
- `lib/vice_activity_editor_page.dart:50` — `void initializeFromActivity(ViceActivity activity) {\n    if (initialized) {\n      return;\n    }\n\n    initialDateText = dateFormat.format(activity.createdAt.toDate());`
