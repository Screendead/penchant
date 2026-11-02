# The unarchived-vices query needs a three-field composite index that is not declared

**Severity:** high

`unarchivedViceListProvider` filters equality on `ownerID` and `archived` and orders by `createdAt` descending, a three-field composite shape. `firestore.indexes.json` declares one vices index covering `ownerID` and `createdAt`, which cannot serve that query, and there is no `archived`-plus-`createdAt` composite for index merging either.

The provider backs the today radar chart's axes and the vice picker in the record-activity dialog, the two most-used read paths. Either the query fails with `failed-precondition` against the declared configuration, or a matching index exists only in the console and the checked-in file is stale, in which case replaying it prunes the live index. CLAUDE.md states that every new composite query shape needs a matching entry, and this already-committed query violates it.

## Evidence

- `lib/providers/unarchived_vice_list_provider.dart:15` — `.collection('vices').where('ownerID', isEqualTo: user.uid).where('archived', isEqualTo: false).orderBy('createdAt', descending: true)`
- `firestore.indexes.json:4` — `"collectionGroup": "vices", "queryScope": "COLLECTION", "fields": [{"fieldPath": "ownerID", "order": "ASCENDING"}, {"fieldPath": "createdAt", "order": "DESCENDING"}]`
- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `lib/widgets/record_new_activity_dialog.dart:65` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `CLAUDE.md:63` — `Any new composite query shape needs a matching entry in firestore.indexes.json; Firestore throws failed-precondition at runtime until the index is deployed.`
