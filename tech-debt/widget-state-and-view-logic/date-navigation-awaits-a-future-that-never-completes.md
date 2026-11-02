# Day navigation gates its whole control surface on an await that can never resolve

**Severity:** high

`_selectDate` sets `loadingDate` to true and then awaits `ref.read(viceActivityDayProvider(nextDate).future)` with no timeout. When the vice list is null or empty the provider returns a const empty stream, which closes without emitting, and in riverpod 3.1.0 the future completer resolves only on data, on error, or at dispose, while no provider in the app is `autoDispose`. The same await also never resolves offline for a day with nothing cached, since the snapshot stream emits nothing until a server round trip succeeds.

`loadingDate` stays true for the rest of the session, disabling the dropdown, both arrows and the Jump to Today button with no message and no cancel affordance.

## Evidence

- `lib/vice_tracker.dart:45` — `await ref.read(viceActivityDayProvider(nextDate).future);`
- `lib/vice_tracker.dart:41` — `loadingDate = true;`
- `lib/providers/vice_activity_day_provider.dart:15` — `return const Stream<List<ViceActivity>?>.empty();`
- `lib/vice_tracker.dart:104` — `onChanged: loadingDate\n                        ? null\n                        : (DateTime? newValue) {`
- **`sed -n '235,330p' ~/.pub-cache/hosted/pub.dev/riverpod-3.1.0/lib/src/core/element.dart`** → `// The listened stream completed during a "loading" state.\n        completer.completeError(_missingLastValueError(), StackTrace.current);`
- **`grep -rl 'autoDispose' lib/ | wc -l`** → `0`
