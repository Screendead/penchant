# The record-activity AlertDialog wraps a Column with no scroll container

**Severity:** high

The dialog's content is a `Form` around a `Column` with minimum main-axis size holding a dropdown and two text fields, with no `SingleChildScrollView` and no scrollable flag on the `AlertDialog`, which does not scroll its content by default.

At an increased system text scale, a routine accessibility setting on both mobile platforms, the taller fields can exceed the available height and overflow the `RenderFlex`, in the one dialog every user needs in order to log an activity.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:79` — `content: Form(\n            key: formKey,\n            child: Column(\n              mainAxisSize: MainAxisSize.min,`
