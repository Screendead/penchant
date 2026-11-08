---
name: seed-emulators
description: Load seed data (a seed user, vices and 30 days of activities) into the local Firebase emulators with admin/populateFirestore.js. Use when the emulators need test data or someone asks how to log in as the seed user.
---

Seed data, into emulators only (Node 22, `npm --prefix admin ci` once). `emulators:exec` sets the emulator hosts
itself but discards the data when the script exits, so it only checks that the script runs:

```bash
firebase emulators:exec --project demo-tracker --only auth,firestore "node admin/populateFirestore.js"
```

To keep the data, start `tools/run-emulated.sh` (or `firebase emulators:start --project demo-tracker`), then in
another terminal point the script at its ports and log in as the seed user:

```bash
FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 node admin/populateFirestore.js
```

`admin/populateFirestore.js` refuses to start unless `FIRESTORE_EMULATOR_HOST` and
`FIREBASE_AUTH_EMULATOR_HOST` are set and the project id (`SEED_PROJECT_ID`, default `demo-tracker`)
starts with `demo-`; it needs no credentials. It creates the Auth user `seed@example.com` (password
`seed-password`) and replaces that user's vices (one archived) and 30 days of activities with documents in the
current data shape.
