# The live-clock date field, its lock toggle and picker flow exist twice with two copies of the format

**Severity:** medium

`vice_activity_editor_page.dart` and `widgets/record_new_activity_dialog.dart` each define the same `dd/MM/yyyy, HH:mm:ss` `DateFormat` constant, a `Timer.periodic` that ticks the field to the current time, a `manualDate` lock-toggle icon, and the date-picker-then-time-picker-then-combine flow — roughly fifty lines of near-identical logic maintained twice.

Each copy both formats for display and parses the typed text for validation and for the Firestore write, so two independent literals govern how `createdAt` is rendered and read back for the same collection. The dialog exposes its format as a static that the editor does not use, declaring its own instead.

## Evidence

- `lib/vice_activity_editor_page.dart:25` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- `lib/widgets/record_new_activity_dialog.dart:17` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- `lib/vice_activity_editor_page.dart:66` — `dateUpdaterTimer = Timer.periodic(const Duration(seconds: 1), (timer) {`
- `lib/widgets/record_new_activity_dialog.dart:74` — `dateUpdaterTimer = Timer.periodic(Duration(seconds: 1), (Timer timer) {`
- `lib/vice_activity_editor_page.dart:120` — `'createdAt': dateFormat.parse(dateController.text),`
- `lib/widgets/record_new_activity_dialog.dart:104` — `final DateTime date = RecordNewActivityDialog.dateFormat.parse(`
