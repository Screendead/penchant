# Vice parsing throws on pending, absent, or unrecognised field values

**Severity:** high

`Vice.fromJson` casts `json['createdAt']` to `Timestamp` and `json['archived']` to `bool`, and resolves the unit through a `firstWhere` with no `orElse`. Creating a vice writes `FieldValue.serverTimestamp()`, and latency compensation delivers a local snapshot in which that field reads null under the default server-timestamp behaviour, so the cast throws for the interval between the local write and the server acknowledgement.

`fromQuerySnapshot` maps every document with no per-document guard, so one bad row errors the whole list for every consumer rather than the single row. The stream is not closed by the error and the following server snapshot carries a real `Timestamp`, so the provider recovers on its own — but pinned riverpod (3.1.0) carries the previous value through the error via `AsyncError.copyWithPrevious`, and every consumer reads only `.value`, never the error itself, so nothing error-shaped ever renders. The vice list just keeps its old contents until the server snapshot lands, so Save appears to do nothing for a round trip; the null value also has no defined position under the `createdAt` ordering the query applies.

## Evidence

- `lib/add_vice.dart:45` — `'createdAt': FieldValue.serverTimestamp(),`
- `lib/data/vice.dart:30` — `createdAt: json['createdAt'] as Timestamp,`
- `lib/data/vice.dart:31` — `archived: json['archived'] as bool,`
- `lib/data/vice.dart:38` — `return snapshot.docs.map((doc) {`
- `lib/data/unit.dart:24` — `return Unit.values.firstWhere(`
- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `~/.pub-cache/hosted/pub.dev/riverpod-3.1.0/lib/src/core/async_value.dart:873` — `return AsyncError._(_error, loading: _loading, value: previous._value);`
- **`grep -rn 'ServerTimestampBehavior' ~/.pub-cache/hosted/pub.dev/cloud_firestore_platform_interface-*/lib/src/get_options.dart`** → `If omitted or set to [ServerTimestampBehavior.none], null will be returned by default until the server value becomes available.`
