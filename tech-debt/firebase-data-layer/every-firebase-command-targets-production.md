# The emulator suite is configured but unused and the only project alias is production

**Severity:** medium

`firebase.json` declares ports for the auth, functions, firestore, hosting and storage emulators plus the emulator UI, but no file in `lib/` calls `useEmulator` or references `localhost`, and `firebase_options.dart` hardcodes the production project on every platform.

`.firebaserc` maps only `default` to `screendead-vice-tracker` with no staging or dev alias, `singleProjectMode` is on, and both workflows hardcode the same project id rather than reading the alias. All local development, manual testing and every firebase command consequently read and write the live project.

## Evidence

- `firebase.json:34` — `"emulators": { "auth": { "port": 9099 },`
- **`grep -rn "useEmulator\|Emulator\|localhost\|127.0.0.1" lib/ pubspec.yaml`** → `(exit 1, no matches)`
- `lib/firebase_options.dart:50` — `projectId: 'screendead-vice-tracker',`
- `.firebaserc:2` — `"projects": { "default": "screendead-vice-tracker" }`
- `firebase.json:53` — `"singleProjectMode": true`
- `.github/workflows/firebase-hosting-pull-request.yml:30` — `projectId: screendead-vice-tracker`
