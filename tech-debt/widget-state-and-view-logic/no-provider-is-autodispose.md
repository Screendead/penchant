# Every family instance holds a Firestore listener open for the whole session

**Severity:** medium

Every provider is a plain `StreamProvider` or `StreamProvider.family` and nothing in `lib/` uses `autoDispose`; riverpod 3.1.0 only schedules disposal when `isAutoDispose` is set. Each distinct family key therefore creates an element holding an open snapshots subscription until the app is killed: one per day stepped through on the Today tab, one per vice-and-range combination on the Graph tab, and one per vice whose history has been opened.

The date dropdown offers 30 days, so a session browsing history accumulates up to 30 concurrent live queries on the activities collection where the previous code kept one. `_selectDate` also reads day providers before any widget watches them, creating subscriptions that never had a consumer.

## Evidence

- **`grep -rl 'autoDispose' lib/ | wc -l`** → `0`
- `lib/providers/vice_activity_day_provider.dart:9` — `final viceActivityDayProvider =\n    StreamProvider.family<List<ViceActivity>?, DateTime>((ref, selectedDate) {`
- `lib/usage_graph_view.dart:95` — `viceActivityGraphProvider(`
- `lib/vice_tracker.dart:45` — `await ref.read(viceActivityDayProvider(nextDate).future);`
- `lib/vice_tracker.dart:111` — `items: List.generate(30, (index) {`
- **`grep -n 'mayNeedDispose' -A8 ~/.pub-cache/hosted/pub.dev/riverpod-3.1.0/lib/src/core/element.dart`** → `if (provider.isAutoDispose) {`
