# The usage graph draws below zero and repeats or overlaps its axis labels

**Severity:** medium

Three drawing faults show up on the Graph tab with the sparse data a new user has, such as a single recorded day in a 30-day range:

- **The curve dips below zero.** Both lines are drawn as curves through the daily totals. Around a lone spike between zero days the curve overshoots and swings under the x-axis, so the graph shows negative use on days with nothing recorded. The chart does not clip its lines to the plot area, so the dip is drawn below the axis line too.
- **The y-axis repeats its top label.** fl_chart always adds a label at the axis maximum as well as at each interval. The maximum is the largest total times 1.15, and the label formatter truncates to an integer, so with a largest total of 1 the axis reads 0, 1, 1 (and with 2 it reads 0, 1, 2, 2).
- **The last two date labels overlap.** The x-axis interval is a quarter of the bucket count, and fl_chart again adds a label at the maximum. At the default 30 daily buckets the labels fall on indices 0, 7, 14, 21 and 28, plus 29 for the maximum, so the last two dates print a day apart on top of each other.

The graph is the screen meant for seeing trends, and each fault misstates the data or makes it harder to read.

## Evidence

- `lib/usage_graph_view.dart:281` — `maxY: maxY == 0 ? 1 : maxY * 1.15,`
- `lib/usage_graph_view.dart:295` — `interval: max(1, (maxY / 4).ceil()).toDouble(),`
- `lib/usage_graph_view.dart:299` — `value.toInt().toString(),`
- `lib/usage_graph_view.dart:309` — `interval: max(1, rawSpots.length ~/ 4).toDouble(),`
- `lib/usage_graph_view.dart:333` — `isCurved: true,` (no `preventCurveOverShooting`, which defaults to `false`)
- fl_chart 1.2.0 `lib/src/chart/base/axis_chart/axis_chart_helper.dart:56` — `if (maxIncluded && !lastPositionOverlapsWithMax) {\n      yield max;\n    }` (`maxIncluded` defaults to `true`)
- fl_chart 1.2.0 `lib/src/chart/line_chart/line_chart_data.dart:59` — `super.clipData = const FlClipData.none(),`
