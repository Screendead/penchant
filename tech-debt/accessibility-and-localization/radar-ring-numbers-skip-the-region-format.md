# The radar's ring numbers print with a decimal and skip the region's number format

**Severity:** low

fl_chart draws the radar's tick labels itself with `tick.toStringAsFixed(1)`, so a ring at 5 reads "5.0", and a large ring skips the digit grouping and decimal mark that every other number in the app gets from `formatCount`. fl_chart 1.3.0 has no formatter hook for radar ticks.

## Evidence

- `~/.pub-cache/hosted/pub.dev/fl_chart-1.3.0/lib/src/chart/radar_chart/radar_chart_painter.dart:210` — `text: tick.toStringAsFixed(1),`
- `lib/vice_chart.dart:277` — `tickCount: scale.top ~/ scale.step,` (the ticks are whole numbers)
