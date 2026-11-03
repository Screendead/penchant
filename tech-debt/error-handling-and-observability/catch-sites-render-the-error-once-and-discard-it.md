# Eighteen catch blocks format the exception into a one-shot SnackBar or Text and drop it

**Severity:** medium

Across `manage_data.dart`, `add_vice.dart`, the editor and history pages, the record dialog, `sign_in.dart`, `register.dart`, `settings.dart` and `account_settings.dart`, every block that handles a `FirebaseException`, `FirebaseAuthException` or untyped exception formats it for display and lets the object fall out of scope. The account screens map it through `authErrorMessage`, which keeps Firebase's text off the screen but drops the code and stack all the same.

None writes the error anywhere else, so once the message leaves the screen the only remaining record is whatever the user happened to notice.

## Evidence

- `lib/manage_data.dart:105` — `SnackBar(content: Text(e.toString())),`
- `lib/vice_activity_editor_page.dart:88` — `error = e.message ?? 'Unable to delete activity';`
- `lib/vice_activity_history_page.dart:90` — `e.message ?? 'Unable to delete activity',`
- `lib/widgets/record_new_activity_dialog.dart:128` — `: 'Error recording activity: ${e.message}';`
- `lib/sign_in.dart:53` — `setState(() => error = authErrorMessage(e));`
- `lib/account_settings.dart:138` — `_show(<String>[...done, 'Not saved: ${authErrorMessage(e)}'].join(' '));`
- `lib/settings.dart:58` — `SnackBar(content: Text(AccountCopy.signOutFailed(authErrorMessage(e)))),`
