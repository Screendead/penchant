# Vices without the archived field never reach the Today tab or the record dialog

**Severity:** medium

`Vice.fromJson` reads a vice with no `archived` field as unarchived, but `unarchivedViceListProvider` selects with `where('archived', isEqualTo: false)`, which Firestore evaluates on the server and which matches only documents whose field holds `false`. A vice written before 2024-08-14, or by the seed script, therefore appears on the Graph tab and in Manage Data (via `viceListProvider`, which has no `archived` filter) but never on the today chart or in the record dialog, so nothing can be recorded against it. No migrator writes the field to existing documents.

## Evidence

- `lib/providers/unarchived_vice_list_provider.dart:17` — `.where('archived', isEqualTo: false)`
- `lib/data/vice.dart:33` — `archived: readBool(json['archived'], fallback: false),`
- `admin/populateFirestore.js:27` — `name: vice.name, unit: vice.unit, ownerID: ownerID, createdAt: Timestamp.now()`
- **`git log --format="%h %ad %s" --date=short --follow -- lib/data/vice.dart`** → `4489c50 2024-08-14 Add archived field to Vice class`
