# No sign-out path clears persistence or terminates the Firestore instance

**Severity:** medium

No file in `lib/` calls `clearPersistence`, `terminate`, or
`setPersistence`. On iOS and macOS, `cloud_firestore` enables on-device
persistence by default, and the single-line sign-out never instructs it to
drop cached documents, so a signed-out user's previously synced vices and
activities remain cached on the device.

## Evidence

- **`grep -rn "clearPersistence\|terminate\|setPersistence" lib/`** → `(no matches)`
- `lib/settings.dart:54` — `FirebaseAuth.instance.signOut();`
