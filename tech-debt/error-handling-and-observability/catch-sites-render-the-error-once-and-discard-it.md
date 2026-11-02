# Eleven catch blocks format the exception into a one-shot SnackBar or Text and drop it

**Severity:** medium

Across `manage_data.dart`, `add_vice.dart`, the editor and history pages, `sign_in.dart`, `account_settings.dart`, `vice_tracker.dart` and the record dialog, every block that handles a `FirebaseException`, `FirebaseAuthException` or untyped exception formats it for display and lets the object fall out of scope.

None writes the error anywhere else, so once the message leaves the screen the only remaining record is whatever the user happened to notice.

## Evidence

- `lib/manage_data.dart:94` — `content: Text(e.toString()),`
- `lib/vice_activity_editor_page.dart:82` — `error = e.message ?? 'Unable to delete activity';`
- `lib/vice_activity_history_page.dart:101` — `e.message ?? 'Unable to delete activity',`
- `lib/sign_in.dart:105` — `error = e.message;`
- `lib/account_settings.dart:54` — `content: Text('Failed to update profile: $e'),`
- `lib/vice_tracker.dart:50` — `content: Text('Unable to load that day: $error'),`
- `lib/widgets/record_new_activity_dialog.dart:262` — `error = 'Error recording activity: ${e.message}';`
