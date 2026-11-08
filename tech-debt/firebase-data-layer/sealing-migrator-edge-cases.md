# The sealing migrator fails a whole batch on one oversized legacy name and tracks completion per device

**Severity:** low

`PlaintextMigrator.update` seals every content field of a legacy document into one blob, and `Sealer.bucketFor` throws when the JSON passes the largest bucket (4094 bytes). Legacy names were never capped by the rules (the register notes names over 60), so one such document makes its whole 200-document batch fail, and by reading the code the next launch fails in the same place. This case has no test. The done marker is kept in a local file per uid and version, so a second device, or the same account after a reinstall, runs the migrator again and relies on it skipping documents that already hold `sealed`.

## Evidence

- `lib/crypto/sealer.dart:159-168` — `bucketFor` throws past `buckets.last - 2`
- `lib/crypto/plaintext_migrator.dart:101` — `update` seals without a length check
- `lib/crypto/plaintext_migration.dart:64` — `isDone` reads a per-device marker
