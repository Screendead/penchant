# Empty scaffold blocks and missing trailing newlines in the Firebase config files

**Severity:** low

`firebase.json` ends with an empty `extensions` block and `firestore.indexes.json` with an empty `fieldOverrides` array, both untouched CLI scaffolding that declares nothing.

`firestore.rules` and `firestore.indexes.json` lack a trailing newline, so diffs on their last line read as a modification rather than an addition and POSIX line-based tooling treats the final line as incomplete.

## Evidence

- `firebase.json:55` — `"extensions": {}`
- `firestore.indexes.json:36` — `"fieldOverrides": []`
- **`for f in firestore.rules firebase.json .firebaserc storage.rules firestore.indexes.json; do printf "%s: " "$f"; if [ -n "$(tail -c 1 "$f")" ]; then echo "NO trailing newline"; else echo "ok"; fi; done`** → `firestore.rules: NO trailing newline\nfirebase.json: ok\n.firebaserc: ok\nstorage.rules: ok\nfirestore.indexes.json: NO trailing newline`
