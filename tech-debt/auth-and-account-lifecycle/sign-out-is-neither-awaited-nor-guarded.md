# signOut is fire-and-forget

**Severity:** medium

`settings.dart` calls `signOut` without awaiting it and without a
try/catch, so a failure in the local sign-out call itself (e.g. a plugin
or platform-channel error) becomes an unhandled asynchronous error with no
user-facing feedback, and the Settings page stays open as if nothing was
pressed.

## Evidence

- `lib/settings.dart:41` — `onTap: () => FirebaseAuth.instance.signOut(),`
