# Chart axis titles are not width-bounded, so long vice names can run into their neighbours

**Severity:** medium

The Today chart labels each bar with the vice name and the quantity with its unit, and the label is a `Text` inside fl_chart's `SideTitleWidget` with no width limit. The `maxLines: 2` and ellipsis cap the height only. On a narrow screen, or with several vices or a long name, neighbouring labels can overlap and the name is hard to read.

This was reported by an earlier agent. It was **reported, not reproduced**: no simulator was run, and the overlap is inferred from reading the code. The usage graph's own axis labels are short numbers and dates with no width limit either, and their overlap is already covered by `usage-graph-misdraws-sparse-data.md`.

## Evidence

- `lib/vice_chart.dart:28` — `'${vice.name} (${vice.unit.label(quantity)})'` builds the label from a free-text name (up to 60 UTF-16 code units).
- `lib/vice_chart.dart:84-97` — `getTitlesWidget` returns `SideTitleWidget(meta: meta, child: Text(title(...), maxLines: 2, overflow: TextOverflow.ellipsis, ...))` with no `SizedBox`, `ConstrainedBox` or width on the text.
- `lib/vice_chart.dart:70` — `alignment: BarChartAlignment.spaceEvenly` with bars `width: 48` (`:108`), so the space per label shrinks as vices are added.
- `lib/usage_graph_view.dart:384-390` and `:401-422` — the usage graph's `getTitlesWidget` callbacks return an unbounded `Text` the same way.
