# The activity editor reports a queued save as a failure

**Severity:** medium

The activity editor wraps its update in a ten-second timeout and, when it fires, shows "Request timed out" and keeps the page open. The timeout abandons only the local await; the update stays queued in the SDK and commits once the device reconnects. The message reads as a failure for an edit that will in fact land.

A retry writes the same fields to the same document, so it cannot duplicate anything, but a user who instead edits the values again, or backs out believing nothing was saved, gets a result the screen never told them about. The record dialog no longer behaves this way; the editor is the remaining write that does.

## Evidence

- `lib/vice_activity_editor_page.dart:106` — `}).timeout(\n        const Duration(seconds: 10),\n        onTimeout: () => Future.error(TimeoutException(null)),\n      );`
- `lib/vice_activity_editor_page.dart:118` — `} on TimeoutException {\n      setState(() {\n        error = 'Request timed out';\n      });`
