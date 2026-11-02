# The radar chart aggregates and labels by vice name despite holding an ID-keyed map

**Severity:** medium

`todayData` is built as a map from vice name to a count, and activities are accumulated into it by name after an ID lookup, so two vices sharing a name collapse into one axis carrying their combined quantity and the user sees one fewer axis than they have vices. The title callback then resolves an axis back to a `Vice` with `firstWhere` on name and no `orElse`, returning whichever duplicate comes first, so the unit label can come from the wrong vice.

The chart already constructs a `vicesByID` map to resolve each activity correctly, and that map is used for neither the accumulation nor the label lookup.

## Evidence

- `lib/vice_chart.dart:47` — `final Map<String, int> todayData = {\n      for (final Vice vice in vices) vice.name: 0,\n    };`
- `lib/vice_chart.dart:57` — `todayData[vice.name] = (todayData[vice.name] ?? 0) + activity.quantity;`
- `lib/vice_chart.dart:99` — `final List<Vice>? vices = ref.watch(viceListProvider).value;`
- `lib/vice_chart.dart:105` — `final Vice vice = vices.firstWhere(\n              (v) => v.name == todayData.keys.elementAt(index),\n            );`
