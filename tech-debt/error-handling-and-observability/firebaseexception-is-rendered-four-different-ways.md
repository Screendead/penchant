# The same exception type is rendered inconsistently, one rendering force-unwrapped

**Severity:** medium

`manage_data.dart` shows the exception's toString, the editor and history pages show its message with a fallback string, and `add_vice.dart` shows the message with a null assertion on a field Firebase types as nullable. A `FirebaseException` raised without a message therefore throws a second exception from inside the catch block of an unawaited async `onPressed` closure, which has no handler of its own and becomes a discarded unhandled Future error, leaving the Save button apparently inert.

`account_settings.dart` adds a fourth rendering, interpolating the raw exception so its bracketed plugin code, such as the internal requires-recent-login token, reaches the user verbatim.

## Evidence

- `lib/manage_data.dart:94` — `content: Text(e.toString()),`
- `lib/add_vice.dart:56` — `content: Text(e.message!),`
- `lib/vice_activity_history_page.dart:101` — `e.message ?? 'Unable to delete activity',`
- `lib/vice_activity_editor_page.dart:82` — `error = e.message ?? 'Unable to delete activity';`
- `lib/account_settings.dart:54` — `content: Text('Failed to update profile: $e'),`
