# Nothing checks the rules and index files against the live project

**Severity:** low

CI deploys `firestore.rules` and `firestore.indexes.json` on every merge to `master`. A rule or index changed in the
console never appears here, and the next merge overwrites the live rules with this file's. Production holds 5 indexes the file does not list (Jack's `firebase firestore:indexes`, 2026-11-09), none needed by
`lib/` (`test/firestore_indexes_test.dart` covers every query with the file's 3): activities (archived, ownerID,
createdAt desc), activities (ownerID, viceID, createdAt asc), activities (viceID, createdAt desc), vices (archived,
ownerID, createdAt desc), vices (ownerID, archived, createdAt desc). The deploy leaves them because it never runs
with `--force`; removing them is round 13's `live-indexes` call.

## Evidence

- Deploy run 41822697732 — "there are 4 indexes defined in your project that are not present in your firestore indexes file"
- `test/firestore_indexes_test.dart` — checks the file against `lib/`'s queries only, never against the project
