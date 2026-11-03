# Nothing ties an activity to the vice in the route it was opened from

**Severity:** low

`firestore.rules` now requires a new activity's `viceID` to name a vice its writer owns, but activities written before that rule may still carry a `viceID` matching no vice or another account's vice, and updates leave `viceID` unchecked so those stay editable. Such rows are invisible to every activity query the app runs today, since each one also constrains `viceID`; the only queries that would return them are `allViceActivityProvider` and `viceActivityWindowProvider`, which are referenced nowhere outside their own definitions. The radar chart separately skips activities whose `viceID` resolves to no vice in the current list.

On the client side the editor deletes and updates activities by the ID taken straight from the route without checking that the document's `viceID` matches the `viceID` segment the page was opened with, and the history page deletes by ID from a list row with no confirmation. The route contract tying an activity to a vice is checked nowhere.

## Evidence

- `lib/vice_chart.dart:55` — `if (quantity != null) {`
- `lib/vice_activity_editor_page.dart:75` — `.doc(widget.activityID)`
- `lib/vice_activity_history_page.dart:87` — `.doc(activity.id)`
- `lib/main.dart:82` — `viceID: uri.pathSegments[1],`
- `lib/providers/vice_activity_history_provider.dart:78` — `.where('ownerID', isEqualTo: user.uid)`
- **`grep -rn "allViceActivityProvider\|viceActivityWindowProvider" lib/`** → `lib/providers/vice_activity_history_provider.dart:102:final viceActivityWindowProvider =` / `lib/providers/vice_activity_history_provider.dart:70:final allViceActivityProvider = StreamProvider<List<ViceActivity>?>((ref) {` (only definitions, no other usages)
