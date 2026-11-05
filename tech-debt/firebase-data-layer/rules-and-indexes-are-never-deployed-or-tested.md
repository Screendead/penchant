# Nothing checks the index file against the queries or the live project

**Severity:** low

CI deploys `firestore.rules` and `firestore.indexes.json` on every merge to `master`. The rules suite runs against the
emulator, which does not enforce composite indexes, so a query that needs an index the file lacks passes every check
and fails at runtime with `failed-precondition`. A rule or index changed in the console never appears here, and the
next merge overwrites the live rules with this file's. Production also holds 4 indexes the file does not list; the
deploy leaves them because it never runs with `--force`.

## Evidence

- `.github/workflows/rules-tests.yml:38` — `- run: npm test` (emulator only)
- Deploy run 41822697732 — "there are 4 indexes defined in your project that are not present in your firestore indexes file"
