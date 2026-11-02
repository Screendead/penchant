# Both collection matches sit inside a recursive wildcard that contributes no condition

**Severity:** medium

The vices and activities matches are nested inside `match /{document=**}`, whose `document` variable is never referenced. Under rules version 2 the recursive wildcard matches zero or more segments, which is what lets the statements reach the real top-level collections, but the same pattern grants identical access to any subcollection named `vices` or `activities` at any depth beneath any document.

The data model uses two flat top-level collections, so nothing exercises the wider surface today, and any future nesting inherits these permissions without a rule being written. The wrapper is a leftover from the default-deny template, which used it for a blanket deny before the nested matches replaced that line.

## Evidence

- `firestore.rules:5` — `match /{document=**} {`
- `firestore.rules:6` — `match /vices/{vice} {`
- `firestore.rules:11` — `match /activities/{activity} {`
- **`git log -p -2 -- firestore.rules`** → `match /{document=**} {\n-  allow read, write: if false;\n+  match /vices/{vice} {`
