# Axis titles that do scale are given a fixed 40px reserved box

**Severity:** medium

The left and bottom axis titles in `usage_graph_view.dart` build real `Text` widgets through `getTitlesWidget`, which respond to the system text-scale setting, while each reserves a fixed size of 40 regardless.

At larger accessibility text sizes the rendered label exceeds the box fl_chart allocated and the axis numbers and date labels are clipped rather than growing to fit.

## Evidence

- `lib/usage_graph_view.dart:294` — `reservedSize: 40,`
- `lib/usage_graph_view.dart:308` — `reservedSize: 40,`
