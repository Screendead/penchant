# Day boundaries are computed from device-local midnight against client-written timestamps

**Severity:** low

`viceActivityDayProvider` builds its day boundary with `startOfDay`, a `DateTime(year, month, day)` in the device's zone and converts it with `Timestamp.fromDate`, producing an instant that moves whenever the zone or offset changes. The activity timestamps it filters were themselves produced from a locally parsed `DateTime` at write time.

An activity recorded in one zone and viewed in another falls into a different day bucket than the one it was recorded in, and the usage graph's range, which bounds on today's local midnight, shifts the same way. The day totals shown on the radar chart therefore depend on where the device is rather than on a stable definition of a day.

## Evidence

- `lib/data/day.dart:5` — `DateTime startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);`
- `lib/providers/vice_activity_day_provider.dart:20` — `isGreaterThanOrEqualTo: Timestamp.fromDate(startOfSelectedDay),`
- `lib/usage_graph_view.dart:126` — `final DateTime rangeStart = today.subtract(Duration(days: rangeDays - 1));`
- `lib/widgets/record_new_activity_dialog.dart:104` — `final DateTime date = RecordNewActivityDialog.dateFormat`
