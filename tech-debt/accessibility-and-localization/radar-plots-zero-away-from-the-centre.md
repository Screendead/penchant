# The radar puts its centre one tick below the day's smallest value, so 0 plots off-centre

**Severity:** high

`ViceChart` builds its `RadarChartData` without `isMinValueAtCenter`, so fl_chart sets the chart's centre value to the smallest entry minus one tick spacing. On a day where one vice has 0, the centre stands for a negative quantity: the 0 point sits on the first ring rather than at the centre, and that ring is labelled `0.0`.

The chart therefore draws a vice that was not used at all as if it had been, and every other point's distance from the centre overstates its share. With every vice at 1 or more, the smallest one sits on the first ring under its own value instead, and the ring count equals the largest quantity, so a day with 120 minutes draws 120 rings.

## Evidence

- `lib/vice_chart.dart:143` — `final RadarDataSet dataSet = RadarDataSet(` (one data set, no `isMinValueAtCenter`)
- `lib/vice_chart.dart:179` — `tickCount: max(quantities.reduce(max), 1),`
- `fl_chart-1.2.0/lib/src/chart/radar_chart/radar_chart_painter.dart:74` — `getChartCenterValue` returns `dataSetMinValue - tickSpace` unless `isMinValueAtCenter`
- `fl_chart-1.2.0/lib/src/chart/radar_chart/radar_chart_painter.dart:114` — the first tick is `dataSetMinValue`, drawn on ring 1
