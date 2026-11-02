# Two unreferenced activity providers define a query shape no declared index can serve

**Severity:** medium

`allViceActivityProvider` and `viceActivityWindowProvider`, together with the `ActivityWindow` key class that exists only to parameterise the second, occupy roughly half of `vice_activity_history_provider.dart` and are referenced nowhere outside their own definitions. Both query activities with an equality on `ownerID` ordered by `createdAt`, and the only declared activities index leads with `viceID`, which cannot serve a query that does not constrain that field.

The gap costs nothing while the code is dead and becomes a `failed-precondition` the moment either provider is wired to a widget. Because no consumer inspects provider error state, that failure would render as an indefinite spinner.

## Evidence

- `lib/providers/vice_activity_history_provider.dart:70` — `final allViceActivityProvider = StreamProvider<List<ViceActivity>?>((ref) {`
- `lib/providers/vice_activity_history_provider.dart:79` — `.where('ownerID', isEqualTo: user.uid).orderBy('createdAt', descending: false)`
- `lib/providers/vice_activity_history_provider.dart:85` — `class ActivityWindow {`
- `lib/providers/vice_activity_history_provider.dart:102` — `final viceActivityWindowProvider = StreamProvider.family<List<ViceActivity>?, ActivityWindow>((ref, window) {`
- `firestore.indexes.json:22` — `"fieldPath": "viceID",`
- **`grep -rn "allViceActivityProvider\|viceActivityWindowProvider" lib/`** → `lib/providers/vice_activity_history_provider.dart:70:final allViceActivityProvider = StreamProvider<List<ViceActivity>?>((ref) {` (only definitions, no other usages)
