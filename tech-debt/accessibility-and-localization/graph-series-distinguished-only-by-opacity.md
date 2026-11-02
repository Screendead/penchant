# Raw and smoothed lines share one hue with no legend or label

**Severity:** medium

`usage_graph_view.dart` draws both series in the theme's primary colour, differing only by alpha (0.35 against fully opaque) and by one pixel of bar width.

Neither line carries a label, legend entry or semantic name, so a user who cannot distinguish the faint from the solid version of one colour has no way to tell which series is which, and a screen reader is exposed to neither.

## Evidence

- `lib/usage_graph_view.dart:337` — `.withValues(alpha: 0.35),`
- `lib/usage_graph_view.dart:338` — `barWidth: 2,`
- `lib/usage_graph_view.dart:345` — `color: Theme.of(context).colorScheme.primary,`
