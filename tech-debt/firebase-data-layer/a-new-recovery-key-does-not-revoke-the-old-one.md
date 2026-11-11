# A new recovery key does not revoke the old one

**Severity:** low

Generating a new recovery key re-wraps the same journal data key, so a leaked recovery key still opens the journal. The only rotation is "Start a new journal", which abandons the data.

## Evidence

- `lib/crypto/journal_key.dart:42` — the recovery key wraps the existing data key
