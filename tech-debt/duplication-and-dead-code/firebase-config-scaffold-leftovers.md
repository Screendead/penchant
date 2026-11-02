# Empty scaffold blocks in the Firebase config files

**Severity:** low

`firebase.json` ends with an empty `extensions` block and `firestore.indexes.json` with an empty `fieldOverrides` array, both untouched CLI scaffolding that declares nothing.

## Evidence

- `firebase.json:55` — `"extensions": {}`
- `firestore.indexes.json:54` — `"fieldOverrides": []`
