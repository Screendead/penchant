# createUserWithEmailAndPassword has no try/catch and its error field is only ever set to null

**Severity:** high

An email-already-in-use or weak-password `FirebaseAuthException` propagates as an unhandled async error and nothing on screen changes. `register.dart` declares an error field and renders it conditionally at the bottom of the form, but the only assignment in the file sets it to null, so that `Text` can never appear.

`sign_in.dart` catches and displays the same class of failure.

## Evidence

- `lib/register.dart:21` — `String? error;`
- `lib/register.dart:170` — `await FirebaseAuth.instance\n                              .createUserWithEmailAndPassword(`
- `lib/register.dart:177` — `error = null;`
- `lib/register.dart:184` — `if (error != null) Text(error!),`
- `lib/sign_in.dart:103` — `} on FirebaseAuthException catch (e) {`
