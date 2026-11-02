# Vice.toJson, ViceActivity.toJson and ViceActivity.copyWith have no call sites

**Severity:** low

Both data classes carry a `toJson` describing exactly the document shape the write sites re-create as inline map literals, and `ViceActivity` carries a fifteen-line `copyWith` (lines 18-32) added alongside the editor feature.

Nothing in `lib/` or `test/` invokes any of them, and the editor, the one screen that modifies an activity, writes a raw map instead. The canonical serialization sits beside hand-written duplicates of itself and can drift from them without any signal.

## Evidence

- **`grep -rn '\.toJson()' lib/ | wc -l`** → `toJson_calls:0`
- **`grep -rn '\.copyWith(' lib/ | wc -l`** → `copyWith_calls:0`
- `lib/data/vice.dart:43` — `Map<String, dynamic> toJson() {`
- `lib/data/vice_activity.dart:18` — `ViceActivity copyWith({`
- `lib/vice_activity_editor_page.dart:103` — `.update({\n        'createdAt': parsedDate,\n        'quantity': int.parse(quantityController.text),\n      })`
