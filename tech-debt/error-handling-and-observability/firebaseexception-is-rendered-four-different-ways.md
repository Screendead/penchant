# The same exception type is rendered four different ways

**Severity:** medium

`manage_data.dart` shows the exception's toString, the editor and history pages show its message with a fixed fallback string, and `add_vice.dart` falls back to the bare error code instead.

`account_settings.dart` adds a fourth rendering, interpolating the raw exception so its bracketed plugin code, such as the internal requires-recent-login token, reaches the user verbatim.

## Evidence

- `lib/manage_data.dart:94` — `content: Text(e.toString()),`
- `lib/add_vice.dart` — `SnackBar(content: Text(e.message ?? e.code))`
- `lib/vice_activity_history_page.dart:101` — `e.message ?? 'Unable to delete activity',`
- `lib/vice_activity_editor_page.dart:82` — `error = e.message ?? 'Unable to delete activity';`
- `lib/account_settings.dart:54` — `content: Text('Failed to update profile: $e'),`
