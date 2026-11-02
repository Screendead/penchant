# Every provider read uses .value, so failures render identically to loading

**Severity:** high

There is no `when`, `whenData`, `hasError`, `error` or `AsyncError` reference anywhere in `lib/`; every consumer branches only on null. The pinned riverpod 3.1.0 documents that getter as returning the previous value during an error state, or null when there was never one, so the exception never reaches the caller.

A permission-denied from the rules, a failed-precondition from a missing composite index, an auth stream error, and a `TypeError` thrown inside `fromQuerySnapshot` all present as an indefinite `CircularProgressIndicator` with no message, no retry and nothing logged. The one place an error reaches the user is the day-switch snackbar, which is on the future path rather than the watched state.

## Evidence

- **`grep -rn '\.when(\|whenData\|hasError\|AsyncError' lib/ | wc -l`** → `0`
- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `lib/vice_chart.dart:24` — `if (vices == null || activityList == null) {`
- `lib/vice_activity_history_page.dart:21` — `if (viceList == null || activityList == null) {`
- `lib/usage_graph_view.dart:73` — `if (viceList == null) {`
- **`sed -n '540,551p' ~/.pub-cache/hosted/pub.dev/riverpod-3.1.0/lib/src/core/async_value.dart`** → `/// If currently in error/loading state, will return the previous value.\n  /// If there is no previous value available, \`null\` will be returned.\n  ...\n  ValueT? get value => _value?.$1;`
