# Auth mutations call the FirebaseAuth singleton inline in each screen

**Severity:** medium

Firestore writes go through `trackerWritesProvider`, but every auth mutation is still an inline `FirebaseAuth.instance` call in a widget callback: sign-in, registration, sign-out, and the account settings profile update, which also caches `FirebaseAuth.instance` and `currentUser` in fields instead of reading `userProvider`. None of these paths can be driven by a widget test, because there is nothing to override with a fake; only `integration_test/` against the Auth emulator reaches them, and it covers registration alone.

## Evidence

- `lib/sign_in.dart:98` — `await FirebaseAuth.instance\n    .signInWithEmailAndPassword(`
- `lib/register.dart:170` — `await FirebaseAuth.instance\n    .createUserWithEmailAndPassword(`
- `lib/settings.dart:54` — `FirebaseAuth.instance.signOut();`
- `lib/account_settings.dart:12` — `final FirebaseAuth _auth = FirebaseAuth.instance;`
- `lib/account_settings.dart:42` — `_user = _auth.currentUser;`
