# One provider chains orderBy before where while the other seven do the reverse

**Severity:** low

`viceListProvider` places its `orderBy` on `createdAt` ahead of the `ownerID` equality filter; the other seven query builders in `lib/providers` put every `where` clause first and the `orderBy` last.

The resulting query and its index requirement are identical, so nothing changes at runtime, but the set of query shapes is harder to read side by side when checking them against `firestore.indexes.json`, which is the only place the required field order is recorded.

## Evidence

- `lib/providers/vice_list_provider.dart:16` — `.orderBy('createdAt', descending: true)`
- `lib/providers/vice_list_provider.dart:17` — `.where('ownerID', isEqualTo: user.uid)`
- `lib/providers/unarchived_vice_list_provider.dart:16` — `.where('ownerID', isEqualTo: user.uid)`
- `lib/providers/vice_activity_history_provider.dart` — contributes four of the seven where-first builders (`viceActivityHistoryProvider`, `viceActivityGraphProvider`, `allViceActivityProvider`, `viceActivityWindowProvider`)
