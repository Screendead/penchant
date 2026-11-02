# RecordNewActivityDialog takes a BuildContext as a constructor argument and keeps it in a field

**Severity:** medium

The dialog is constructed with the opening button's context and stores it in a final `BuildContext` field. After the awaited write it uses that field to pop the route and show a snackbar whose Undo action captures the same context again for a later delete.

The widget therefore holds a reference to another element's context across async gaps and across its own disposal, and the field shares its name with the build method's context parameter, so the code reaches it as `widget.context`.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:20` — `final BuildContext context;`
- `lib/widgets/record_new_activity_button.dart:19` — `context: context,`
- `lib/widgets/record_new_activity_dialog.dart:280` — `if (widget.context.mounted) {`
- `lib/widgets/record_new_activity_dialog.dart:291` — `if (widget.context.mounted) {`
