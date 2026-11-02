# signOut is fire-and-forget and the route is popped on the next line

**Severity:** medium

`settings.dart` calls `signOut` without awaiting it and without a
try/catch, so a failure in the local sign-out call itself (e.g. a plugin
or platform-channel error) becomes an unhandled asynchronous error with no
user-facing feedback. `Navigator.pop` runs immediately, racing the auth
state change that swaps the app root back to `Authenticate`; the
surrounding state class has no fields and overrides nothing but `build`,
so there is no `mounted` or in-flight flag guarding against that race.

## Evidence

- `lib/settings.dart:11` — `class _SettingsState extends State<Settings> {`
- `lib/settings.dart:54` — `FirebaseAuth.instance.signOut();
                Navigator.of(context).pop();`
