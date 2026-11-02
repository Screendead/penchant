# No query applies a limit, and the editor streams a whole vice history to find one document

**Severity:** medium

No call site in `lib/` uses `limit` or a pagination cursor, so every provider opens an unbounded live listener over its matching document set. `viceActivityHistoryProvider` streams a vice's entire activity history, and the editor page watches it purely to locate the single activity named in the route, a document whose ID it already holds, then scans the list twice.

`viceActivityListProvider` streams every activity across every vice so `manage_data.dart` can render a per-vice count. Read cost and snapshot size grow without bound as history accumulates, on screens that display a handful of values, and the editor is reachable directly by route so the cost is paid on every single-record edit.

## Evidence

- **`grep -rn "\.limit(" lib/ --include='*.dart'`** → `exit=1 (no matches found)`
- `lib/vice_activity_editor_page.dart:148` — `final ViceActivity? activity = activityList.where((ViceActivity item) => item.id == widget.activityID).isEmpty`
- `lib/providers/vice_activity_history_provider.dart:15` — `.collection('activities').where('viceID', isEqualTo: viceID).where('ownerID', isEqualTo: user.uid).orderBy('createdAt', descending: true)`
- `lib/manage_data.dart:16` — `ref.watch(viceActivityListProvider).value;`
- `lib/vice_activity_editor_page.dart:134` — `final List<ViceActivity>? activityList = ref.watch(viceActivityHistoryProvider(widget.viceID)).value;`
