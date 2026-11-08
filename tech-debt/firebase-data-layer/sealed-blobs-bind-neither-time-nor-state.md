# A sealed entry can be moved in time or rolled back without the client noticing

**Severity:** low

The additional authenticated data for a sealed blob is only `collection/documentID`. `createdAt`, `archived` and any version stay plaintext and outside it, so someone with write access to the database can change an entry's `createdAt`, flip a vice's `archived`, or put an earlier valid `sealed` value back on the same document, and the client opens it without complaint. Separately, generating a new recovery key re-wraps the same journal data key, so it does not revoke a leaked recovery key; the only rotation is "Start a new journal", which abandons the data.

## Evidence

- `lib/data/sealed.dart:47` — `sealContext` is `'$collection/$id'`
- `lib/writes/tracker_writes.dart:70` — the context passed when sealing a write
- `lib/crypto/journal_key.dart:42` — the recovery key wraps the existing data key
