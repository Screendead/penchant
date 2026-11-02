# Both fl_chart visuals are painted with no Semantics, semanticLabel, or annotation of any kind

**Severity:** high

The radar chart on the Today tab and the line chart on the Graph tab are CustomPainter-based visuals with no accessibility annotation, so a screen-reader user landing on either of the app's two primary tabs hears nothing of the day's vice quantities or the usage trend.

A repo-wide grep for `Semantics`, `semanticLabel`, `textScal` and `MediaQuery` across `lib/` returns zero matches, so no accessibility API is used anywhere in the codebase. The entire numeric payload the app exists to show is unreachable by VoiceOver and TalkBack.

## Evidence

- `lib/vice_chart.dart:84` — `child: RadarChart(`
- `lib/usage_graph_view.dart:276` — `: LineChart(`
- **`grep -rn "Semantics|semanticLabel|textScal|MediaQuery" lib/ | wc -l`** → `0`
