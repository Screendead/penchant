# Nothing checks the rules and index files against the live project

**Severity:** low

CI deploys `firestore.rules` and `firestore.indexes.json` on every merge to `master`. A rule or index changed in the
console never appears here, and the next merge overwrites the live rules with this file's. Production also holds 4
indexes the file does not list; the deploy leaves them because it never runs with `--force`. The file in turn lists
`vices (ownerID, archived, createdAt DESC)`, which no query in `lib/` uses since the unarchived filter moved onto the
device.

## Evidence

- Deploy run 41822697732 — "there are 4 indexes defined in your project that are not present in your firestore indexes file"
- `test/firestore_indexes_test.dart` — checks the file against `lib/`'s queries only; it reports no unused entry
