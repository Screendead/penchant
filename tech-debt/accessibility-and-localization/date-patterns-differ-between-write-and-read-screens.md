# Day-first order on the two write screens, month-first on the three display screens

**Severity:** low

The editor and the record dialog format and parse a timestamp as day-first while the tracker dropdown, the graph axis and the history list each use a different month-first pattern.

The same stored moment appears one way when edited and three other ways when displayed, four independently hand-rolled patterns with no shared convention.

## Evidence

- `lib/vice_activity_editor_page.dart:28` — `static final DateFormat dateFormat = DateFormat('dd/MM/yyyy, HH:mm:ss');`
- `lib/vice_tracker.dart:114` — `DateFormat('EEEE, MMMM d, yyyy').format(date);`
- `lib/usage_graph_view.dart:125` — `final DateFormat labelFormat = DateFormat('MMM d');`
- `lib/vice_activity_history_page.dart:60` — `'${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',`
