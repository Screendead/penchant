# Archived vices are hidden on the Today tab and selectable on the Graph tab

**Severity:** medium

The Graph tab's vice dropdown is populated from `viceListProvider`, which returns every vice including archived ones, while the today chart and the record dialog both use `unarchivedViceListProvider`. The archived flag therefore hides a vice in two of the three vice pickers and means nothing in the third.

The Graph tab also defaults its selection to the first entry of that list, which can be an archived vice.

## Evidence

- `lib/usage_graph_view.dart:111` — `final List<Vice>? viceList = ref.watch(viceListProvider).value;`
- `lib/usage_graph_view.dart:106` — `return viceList.first.id;`
- `lib/vice_chart.dart:127` — `unarchivedViceListProvider,`
- `lib/widgets/record_new_activity_dialog.dart:184` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
