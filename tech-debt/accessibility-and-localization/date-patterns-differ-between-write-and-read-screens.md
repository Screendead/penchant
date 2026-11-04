# Day-first order on the two write screens, month-first on the three display screens

**Severity:** low

The editor and the record dialog format and parse a timestamp as day-first while the tracker dropdown, the graph axis and the history list each use a different month-first pattern.

The same stored moment appears one way when edited and three other ways when displayed, four independently hand-rolled patterns with no shared convention.

## Evidence

- `lib/vice_activity_editor_page.dart:25` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- `lib/vice_chart.dart:25` — `static final DateFormat dayFormat = DateFormat('EEEE, MMMM d, yyyy');` (the Today tab's date menu reads it)
- `lib/usage_graph_view.dart:17` — `final DateFormat labelFormat = DateFormat('MMM d');`
- `lib/vice_activity_history_page.dart:139` — `'${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',`
