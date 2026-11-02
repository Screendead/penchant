# Providers return an empty stream for an empty vice list, so no-data renders as loading forever

**Severity:** high

`viceActivityDayProvider` and `viceActivityListProvider` return a const empty stream whenever the resolved vice list is empty, not only when the user is null. Riverpod leaves a provider in `AsyncLoading` when its stream closes without emitting, so the value stays null indefinitely and consumers keep rendering a spinner. `ViceChart` spins while either list is null and only tests for an empty vice list afterwards, so its guidance box is unreachable and a fresh account sees an endless spinner on the Today tab.

`ManageData` renders the same spinner and never reaches its own empty branch, and because the only navigation to `/vices/add` is the icon button in that screen's AppBar, an account with zero vices has no path to create its first one. CLAUDE.md documents the opposite contract, that null means loading and an empty list means no data.

## Evidence

- `lib/manage_data.dart:18` — `if (viceList == null || viceActivityList == null) {`
- `lib/manage_data.dart:24` — `if (viceList.isEmpty) {`
- `lib/providers/vice_activity_list_provider.dart:13` — `if (user == null || viceList == null || viceList.isEmpty) {\n    return const Stream<List<ViceActivity>?>.empty();`
- `lib/vice_chart.dart:24` — `if (vices == null || activityList == null) {\n      return const Center(\n        child: CircularProgressIndicator(),\n      );\n    }`
- `lib/vice_chart.dart:30` — `if (vices.isEmpty) {\n      return const InfoBox(\n        message: 'No vices found',`
- `CLAUDE.md:52` — `` Each returns `Stream.empty()` when the user is null, so `.value` stays `null` and widgets render a spinner. A `null` list means loading; an empty list means no data. ``
