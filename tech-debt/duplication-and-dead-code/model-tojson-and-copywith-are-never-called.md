# Vice.toJson and ViceActivity.toJson have no call site in lib/, and ViceActivity.copyWith none outside tests

**Severity:** low

Both data classes carry a `toJson` describing exactly the document shape that `TrackerWrites` re-creates as map literals. Nothing in `lib/` invokes either; the only callers are a round-trip check in `test/model_parsing_test.dart`. `ViceActivity.copyWith` is called only from `test/sync_status_test.dart`.

Every write in `TrackerWrites` spells out its field names by hand. The literal `'archived'` appears in the model's parser and `toJson`, twice in `TrackerWrites`, and in the unarchived provider's `where` clause. The canonical serialization sits beside hand-written duplicates of itself and can drift from them without any signal beyond that one test.

## Evidence

- **`grep -rn '\.toJson()\|\.copyWith(' lib/`** → only `TextStyle.copyWith` calls in `lib/widgets/clean_day.dart`; none on a model
- `lib/data/vice.dart:49` — `Map<String, dynamic> toJson() {`
- `lib/data/vice_activity.dart:22` — `ViceActivity copyWith({`
- `lib/data/vice_activity.dart:65` — `Map<String, dynamic> toJson() => {`
- `lib/writes/tracker_writes.dart:27` — `'archived': false,`
- `lib/writes/tracker_writes.dart:36` — `return _vices.doc(viceID).update({'archived': archived});`
- `lib/writes/tracker_writes.dart:65` — `return _activities.doc(activityID).update({`
- `lib/providers/unarchived_vice_list_provider.dart:11` — `.where('archived', isEqualTo: false)`
