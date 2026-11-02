# Text controllers and focus nodes are created without disposal across the forms

**Severity:** medium

`sign_in.dart`, `register.dart` and `add_vice.dart` declare `TextEditingController`s with no dispose override at all, and `RecordNewActivityDialog.dispose` cancels its timer while leaving both of its controllers undisposed; the editor page is the only one of the group that disposes anything. The dialog's date field is also given a `FocusNode` constructed inline inside build, and that widget calls `setState` on every keystroke and every toggle, so a fresh undisposed node is attached on each rebuild and whatever focus state the field held is dropped.

Both the dialog and the editor additionally request focus on a throwaway `FocusNode` to move focus off the date field before opening a picker, inserting an unnamed undisposed node into the focus tree on every tap, which on the web and macOS targets can appear as a phantom stop in the Tab order with nothing rendered at it.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:327` — `void dispose() {\n    dateUpdaterTimer.cancel();\n    super.dispose();\n  }`
- `lib/widgets/record_new_activity_dialog.dart:120` — `focusNode: FocusNode(),`
- `lib/widgets/record_new_activity_dialog.dart:155` — `FocusScope.of(context).requestFocus(FocusNode());`
- `lib/sign_in.dart:15` — `TextEditingController emailController = TextEditingController();`
- `lib/vice_activity_editor_page.dart:65` — `dateController.dispose();`
- `lib/vice_activity_editor_page.dart:239` — `FocusScope.of(context).requestFocus(FocusNode());`
