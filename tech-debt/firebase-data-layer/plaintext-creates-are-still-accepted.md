# The rules still accept a vice's name and unit, and an activity's triggers, in plaintext

**Severity:** medium

A vice's `name` and `unit`, and an activity's `triggers`, are sealed on the device, but `firestore.rules` accepts both shapes on create: a vice with `name` and `unit` in the clear or with `sealed`, and an activity with `triggers` in the clear or inside `sealed`. The sealed-only rules (R2) were never written, because the dual shape let builds from before encryption keep working while the migrator converted their data. An old or buggy client can therefore still write names and triggers in plaintext, the migrator's per-device done flag will not reconvert them on a device that already finished, and the "we cannot read what you log" claim holds only for clients that seal. Once no build in the field writes plaintext, a vice create without `sealed` could be refused. An activity's `quantity` and decimal `amount` are plaintext on purpose (the bead-summary function reads them), so they are not part of this.

## Evidence

- `firestore.rules:94-99` — the vice create branch with `name`, `unit` and no `sealed`
- `firestore.rules:135-137` — the activity create allows `triggers` without `sealed` (`sealedAlone` forbids only both at once)
- `lib/crypto/plaintext_migration.dart:64` — `isDone` reads a marker kept on the device
