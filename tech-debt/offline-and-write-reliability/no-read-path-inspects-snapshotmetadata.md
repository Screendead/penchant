# Cached and server data are indistinguishable, and an empty cache renders as an authoritative empty state

**Severity:** high

Every provider calls `snapshots()` with default arguments and pipes straight into a `fromQuerySnapshot` factory that reads only the docs and discards the metadata, so `isFromCache` and `hasPendingWrites` never reach the model layer or the UI. A repo-wide grep for those names and for `includeMetadataChanges` returns nothing.

When the day's activity list is empty, `ViceChart` renders its no-activities message unconditionally, with no branch for an empty local cache rather than a confirmed server answer. Offline on a platform with persistence on, navigating to a day never previously fetched produces exactly that empty snapshot.

## Evidence

- `lib/providers/vice_activity_day_provider.dart:36` — `.snapshots()\n      .map(ViceActivity.fromQuerySnapshot);`
- `lib/data/vice_activity.dart:46` — `static List<ViceActivity> fromQuerySnapshot(\n    QuerySnapshot<Map<String, dynamic>> snapshot,\n  ) {\n    return snapshot.docs.map((doc) {`
- `lib/vice_chart.dart:37` — `if (activityList.isEmpty) {\n      return const InfoBox(\n        message: 'No activities found',\n        color: Colors.red,\n      );\n    }`
