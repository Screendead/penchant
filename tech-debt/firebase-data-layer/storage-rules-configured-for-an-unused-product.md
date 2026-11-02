# storage.rules is untouched scaffold for a product the app does not use

**Severity:** low

`storage.rules` contains a commented-out example condition and a blanket deny. Neither `pubspec.yaml` nor `lib/` references `firebase_storage` or `FirebaseStorage`; the only matches are the `storageBucket` strings generated into `firebase_options.dart`.

`firebase.json` still registers the file, so every firebase deploy includes a Storage rules deploy, and the emulator config reserves a port for it.

## Evidence

- `storage.rules:9` — `allow read, write: if false;`
- `storage.rules:3` — `// Craft rules based on data in your Firestore database // allow write: if firestore.get(...).data.isAdmin;`
- `firebase.json:31` — `"storage": { "rules": "storage.rules" },`
- **`grep -rn "firebase_storage\|FirebaseStorage\|storage" pubspec.yaml lib/`** → `lib/firebase_options.dart:52:storageBucket: 'screendead-vice-tracker.appspot.com',`
