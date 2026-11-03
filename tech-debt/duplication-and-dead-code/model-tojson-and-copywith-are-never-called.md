# Vice.toJson, ViceActivity.toJson and ViceActivity.copyWith have no call sites

**Severity:** low

Both data classes carry a `toJson` describing exactly the document shape that `TrackerWrites` re-creates as map literals, and `ViceActivity` carries a fifteen-line `copyWith` (lines 18-32) added alongside the editor feature.

Nothing in `lib/` or `test/` invokes any of them; every write in `TrackerWrites` spells out its field names by hand. The literal `'archived'` appears in the model's parser and `toJson`, twice in `TrackerWrites`, and in the unarchived provider's `where` clause. The canonical serialization sits beside hand-written duplicates of itself and can drift from them without any signal.

## Evidence

- **`grep -rn '\.toJson()' lib/ | wc -l`** → `toJson_calls:0`
- **`grep -rn '\.copyWith(' lib/ | wc -l`** → `copyWith_calls:0`
- `lib/data/vice.dart:43` — `Map<String, dynamic> toJson() {`
- `lib/data/vice_activity.dart:18` — `ViceActivity copyWith({`
- `lib/writes/tracker_writes.dart:22` — `return _vices.add({\n      'name': name,`
- `lib/writes/tracker_writes.dart:32` — `return _vices.doc(viceID).update({'archived': archived});`
- `lib/writes/tracker_writes.dart:59` — `return _activities.doc(activityID).update({\n      'createdAt': createdAt,`
- `lib/data/vice.dart:31` — `archived: json['archived'] as bool,`
- `lib/providers/unarchived_vice_list_provider.dart:17` — `.where('archived', isEqualTo: false)`
