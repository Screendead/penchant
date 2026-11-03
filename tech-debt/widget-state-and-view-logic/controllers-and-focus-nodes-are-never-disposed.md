# Text controllers and focus nodes are created without disposal across the forms

**Severity:** medium

`RecordNewActivityDialog.dispose` cancels its timer while leaving both of its controllers undisposed; every other form disposes its controllers. The dialog's date field is also given a `FocusNode` constructed inline inside build, and that widget calls `setState` on every keystroke and every toggle, so a fresh undisposed node is attached on each rebuild and whatever focus state the field held is dropped.

Both the dialog and the editor additionally request focus on a throwaway `FocusNode` to move focus off the date field before opening a picker, inserting an unnamed undisposed node into the focus tree on every tap, which on macOS can appear as a phantom stop in the Tab order with nothing rendered at it.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:364` — `void dispose() {\n    dateUpdaterTimer.cancel();\n    super.dispose();\n  }`
- `lib/widgets/record_new_activity_dialog.dart:241` — `focusNode: FocusNode(),`
- `lib/widgets/record_new_activity_dialog.dart:276` — `FocusScope.of(context).requestFocus(FocusNode());`
- `lib/vice_activity_editor_page.dart:76` — `dateController.dispose();`
- `lib/vice_activity_editor_page.dart:275` — `FocusScope.of(context).requestFocus(FocusNode());`
