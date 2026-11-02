# Nothing ties an activity's viceID to a vice the writer owns or to the route it came from

**Severity:** low

The activity write rule inspects `ownerID` alone, so `viceID` passes through unchecked and can carry any string, including another account's vice ID or an ID matching no vice. Such rows are invisible to every activity query the app runs today, since each one also constrains `viceID`; the only queries that would return them are `allViceActivityProvider` and `viceActivityWindowProvider`, which are referenced nowhere outside their own definitions. The radar chart separately skips activities whose `viceID` resolves to no vice in the current list.

On the client side the editor deletes and updates activities by the ID taken straight from the route without checking that the document's `viceID` matches the `viceID` segment the page was opened with, and the history page deletes by ID from a list row with no confirmation. Ownership is enforced only by `firestore.rules`; the route contract tying an activity to a vice is checked nowhere.

## Evidence

- `firestore.rules:13` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `lib/widgets/record_new_activity_dialog.dart:255` — `'viceID': selectedVice!.id,`
- `lib/vice_chart.dart:43` — `if (vice == null) {`
- `lib/vice_activity_editor_page.dart:74` — `.doc(widget.activityID)`
- `lib/vice_activity_history_page.dart:87` — `.doc(activity.id)`
- `lib/main.dart:85` — `viceID: uri.pathSegments[1],`
- `lib/providers/vice_activity_history_provider.dart:79` — `.where('ownerID', isEqualTo: user.uid).orderBy('createdAt', descending: false)`
- **`grep -rn "allViceActivityProvider\|viceActivityWindowProvider" lib/`** → `lib/providers/vice_activity_history_provider.dart:102:final viceActivityWindowProvider =` / `lib/providers/vice_activity_history_provider.dart:70:final allViceActivityProvider = StreamProvider<List<ViceActivity>?>((ref) {` (only definitions, no other usages)
