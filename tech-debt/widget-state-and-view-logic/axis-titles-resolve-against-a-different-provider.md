# Chart axes come from the unarchived vice list while their titles are looked up in the full list

**Severity:** medium

`ViceChart` builds its axes from `unarchivedViceListProvider` but the title callback looks each vice up in `viceListProvider`, which includes archived vices. The two lists are separate Firestore listeners that can be out of step, and the lookup is a `firstWhere` with no `orElse`, so a name present in the unarchived snapshot but not yet in the full snapshot throws a `StateError` from inside a paint callback.

A renamed vice or an archived-unarchived name collision produces the same mismatch.

## Evidence

- `lib/vice_chart.dart:20` — `final List<Vice>? vices = ref.watch(unarchivedViceListProvider).value;`
- `lib/vice_chart.dart:99` — `final List<Vice>? vices = ref.watch(viceListProvider).value;`
- `lib/vice_chart.dart:105` — `final Vice vice = vices.firstWhere(\n              (v) => v.name == todayData.keys.elementAt(index),\n            );`
