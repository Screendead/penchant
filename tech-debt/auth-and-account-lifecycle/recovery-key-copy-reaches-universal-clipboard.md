# The recovery key is copied with a plain clipboard write

**Severity:** low

The recovery screen copies the formatted key with `Clipboard.setData`. On iOS and macOS a plain pasteboard write can reach the user's other devices through Universal Clipboard and stays until overwritten, so the secret that unlocks the whole journal is copied to wherever the user's Apple devices sync it. The platform offers a local-only, expiring pasteboard write; the code uses neither.

## Evidence

- `lib/journal_key/recovery_key_screens.dart:316` — `Clipboard.setData(ClipboardData(text: status.formatted))`
