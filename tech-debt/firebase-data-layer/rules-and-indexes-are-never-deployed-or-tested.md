# Nothing checks the rules and index files against the live project

**Severity:** low

CI deploys `firestore.rules` and `firestore.indexes.json` on every merge to `master`. A rule or index changed in the
console never appears here, and the next merge overwrites the live rules with this file's. Production's indexes matched the file on 2026-11-09, after a `--force` indexes deploy (Jack's leave) deleted the
5 unused ones; nothing keeps them matched.

## Evidence

- `test/firestore_indexes_test.dart` — checks the file against `lib/`'s queries only, never against the project
