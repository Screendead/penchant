# The by-vice-ID grouping provider lost its only consumer while ManageData re-derives the same grouping

**Severity:** medium

At HEAD, `vice_chart.dart` consumed `viceActivityListByViceIDProvider`; the working-tree rewrite switched the chart to `viceActivityDayProvider` and left the file tracked with no consumer anywhere in `lib/` or `test/`.

`ManageData`, the one screen that needs activities grouped per vice, filters the flat list with a `where` inside `itemBuilder` for every row rather than reading the provider that already computes that map. The provider's own dependency, `viceActivityListProvider`, is still used elsewhere, so the dead code is confined to the one file.

## Evidence

- `lib/providers/vice_activities_by_vice_id_provider.dart:5` — `final viceActivityListByViceIDProvider =`
- **`git grep -n viceActivityListByViceIDProvider HEAD -- lib`** → `HEAD:lib/vice_chart.dart:41:        ref.watch(viceActivityListByViceIDProvider);`
- **`grep -rn viceActivityListByViceIDProvider lib/ test/`** → `lib/providers/vice_activities_by_vice_id_provider.dart:5:final viceActivityListByViceIDProvider =`
- `lib/manage_data.dart:53` — `final List<ViceActivity> viceActivities = viceActivityList`
- **`git diff lib/vice_chart.dart`** → `-import 'package:tracker/providers/vice_activities_by_vice_id_provider.dart';`
