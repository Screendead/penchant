# Activity queries pass every vice ID, archived ones included, to a 30-element whereIn filter

**Severity:** medium

`viceActivityDayProvider` and `viceActivityListProvider` build their filters from the full vice list and pass it to `whereIn`, which `cloud_firestore` caps at 30 elements through an assert. Debug builds trip the assertion; release builds send an oversized filter and receive `invalid-argument` from the backend.

Both read `viceListProvider` rather than the unarchived list, so archived vices consume the budget and their activities are fetched over the network on every date change and then discarded by the chart's ID lookup. No path in `lib/` deletes a vice, so the ID count only grows, and reaching the cap takes out the today chart and the manage-data screen together.

## Evidence

- `lib/providers/vice_activity_day_provider.dart:28` — `.where('viceID', whereIn: viceIDs)`
- `lib/providers/vice_activity_list_provider.dart:21` — `.where('viceID', whereIn: viceIDs)`
- **`grep -n "maximum of 30 elements" ~/.pub-cache/hosted/pub.dev/cloud_firestore-6.7.1/lib/src/query.dart`** → `"'$operator' filters support a maximum of 30 elements in the value [Iterable].",`
- `lib/providers/vice_activity_day_provider.dart:12` — `final List<Vice>? viceList = ref.watch(viceListProvider).value;`
- `lib/vice_chart.dart:44` — `final Map<String, Vice> vicesByID = { for (final Vice vice in vices) vice.id: vice, };`
