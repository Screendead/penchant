# The day provider is keyed on a raw DateTime it then normalises internally

**Severity:** low

`viceActivityDayProvider` takes a raw `DateTime` key and derives start-of-day from its year, month and day inside the body, so the key carries a time component the query discards. Two keys that differ but land on the same calendar day create two never-disposed elements running byte-identical queries.

`ViceTracker` generates keys through `Duration` arithmetic, subtracting days for the dropdown and adding a day at a time for the arrows, which does not preserve time-of-day across a daylight-saving transition, so reaching the same day by dropdown and by arrow can yield different keys. The dropdown's value must also be object-equal to one of its generated items for the selection to render.

## Evidence

- `lib/providers/vice_activity_day_provider.dart:10` — `StreamProvider.family<List<ViceActivity>?, DateTime>((ref, selectedDate) {`
- `lib/providers/vice_activity_day_provider.dart:18` — `final DateTime startOfDay = DateTime(\n    selectedDate.year,\n    selectedDate.month,\n    selectedDate.day,\n  );`
- `lib/vice_tracker.dart:111` — `final date = today.subtract(Duration(days: index));`
- `lib/vice_tracker.dart:133` — `selectedDate.subtract(const Duration(days: 1)),`
