# The only project alias is production, so every firebase command defaults to it

**Severity:** medium

The app can run against the Auth and Firestore emulators under `demo-tracker`, but only through `tools/e2e.sh` and `tools/run-emulated.sh`. `.firebaserc` maps only `default` to `screendead-vice-tracker` with no staging, dev or demo alias, so any `firebase` command run without `--project` (`deploy`, `firestore:*`, a bare `emulators:start`) targets the live project, and `flutter run` without the dart-define talks to production.

The rules deploy workflow hardcodes the same project id rather than reading an alias, and there is no staging project in which to try a rules or index deploy before production.

## Evidence

- `.firebaserc:2` — `"projects": { "default": "screendead-vice-tracker" }`
- `lib/firebase_options.dart:50` — `projectId: 'screendead-vice-tracker',`
- `.github/workflows/deploy-firestore.yml:43` — `--project screendead-vice-tracker --non-interactive`
- `tools/emulator-env.sh:5` — `E2E_PROJECT=demo-tracker`
