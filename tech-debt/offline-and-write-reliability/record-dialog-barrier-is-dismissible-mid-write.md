# Tapping outside the record dialog pops it while its write is still in flight

**Severity:** medium

`showDialog` is called without `barrierDismissible` set to false and the dialog has no `PopScope`, so the default dismissible barrier pops the route regardless of the awaited `set`. The async callback keeps running after disposal, but only the `finally` block's `loading = false` reset is gated behind a `mounted` check; the two catch blocks' error-message `setState` calls are not, so a failure that lands after the barrier is dismissed throws a setState-after-dispose error instead of being cleanly skipped. The success path is not silent either: it runs off `widget.context`, the parent screen's context passed into the widget, which stays mounted after the dialog pops, so a write that finishes successfully still triggers an extra `Navigator.pop` and a visible 'Activity recorded' snackbar with an Undo action. The loading overlay itself does disappear with the dialog, so nothing on screen signals the write is still pending until one of these side effects fires.

## Evidence

- `lib/widgets/record_new_activity_button.dart:16` — `showDialog(\n          context: context,\n          builder: (_) {`
- `lib/widgets/record_new_activity_dialog.dart:260-263` — `} on FirebaseException catch (e) {\n                  setState(() {\n                    error = 'Error recording activity: ${e.message}';\n                  });`
- `lib/widgets/record_new_activity_dialog.dart:266-269` — `} on TimeoutException {\n                  setState(() {\n                    error = 'Request timed out';\n                  });`
- `lib/widgets/record_new_activity_dialog.dart:273` — `} finally {\n                  if (mounted) {\n                    setState(() {\n                      loading = false;\n                    });\n                  }\n                }`
- `lib/widgets/record_new_activity_dialog.dart:280-282` — `if (widget.context.mounted) {\n                  Navigator.of(widget.context).pop();\n                  ScaffoldMessenger.of(widget.context).showSnackBar(`
