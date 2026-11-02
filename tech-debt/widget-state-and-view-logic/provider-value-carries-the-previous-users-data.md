# Provider values keep returning the prior session's data through and after sign-out

**Severity:** high

`viceListProvider` and every provider chained off `userProvider` is rebuilt when `authStateChanges` emits null and switches to an empty stream. Riverpod carries the previous `AsyncData` forward through the `AsyncLoading` state of a dependency-triggered rebuild, so the value keeps returning the signed-out user's list rather than resetting to null. Consumers such as `vice_chart.dart` and `usage_graph_view.dart` read that value directly, so the UI can keep rendering the previous session's vices and activities across a sign-out and into another user's session on the same device before fresh data arrives.

CLAUDE.md states that the value stays null once the user is null, which holds only on a cold first build.

## Evidence

- `lib/providers/vice_list_provider.dart:10` — `if (user == null) {\n    return const Stream<List<Vice>?>.empty();\n  }`
- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `lib/usage_graph_view.dart:71` — `final List<Vice>? viceList = ref.watch(viceListProvider).value;`
- `CLAUDE.md:52` — `` `userProvider` alone. Each returns `Stream.empty()` when the user is null, so `.value` stays `null` and widgets render a spinner. ``
