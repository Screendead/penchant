# The same exception type is rendered four different ways

**Severity:** low

`manage_data.dart` shows the exception's toString, the editor and history pages show its message with a fixed fallback string, and `vice_form.dart` shows its message with the bare error code as the fallback.

`account_settings.dart` adds a fourth rendering, interpolating the raw exception so its bracketed plugin code, such as the internal requires-recent-login token, reaches the user verbatim.

## Evidence

- `lib/manage_data.dart:37` — `message = e.toString();`
- `lib/vice_form.dart:83` — `messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));`
- `lib/vice_activity_history_page.dart:46` — `message = e.message ?? 'Unable to delete activity';`
- `lib/vice_activity_editor_page.dart:105` — `error = e.message ?? 'Unable to delete activity';`
- `lib/account_settings.dart:54` — `content: Text('Failed to update profile: $e'),`
