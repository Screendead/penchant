# Radar titles are left uncut when even an ellipsis and the quantity do not fit, so they can run into their neighbours

**Severity:** low

fl_chart paints each radar title on one line with no width limit, so the Today radar cuts the vice name with an ellipsis to fit the chord between neighbouring titles, keeping the quantity whole. When the chord is narrower than `…` plus the quantity suffix, the cut cannot make the title fit, and the whole `name (quantity unit)` string is drawn instead. Neighbouring titles can then overlap, as all of them could before the cut existed.

The chord shrinks as unarchived vices are added and the suffix widens with the text size, so this happens with many vices, at large text sizes, or both. The point where it starts was estimated by review (about 7 vices at text scale 2 on a phone), not measured. The bar layout (1 or 2 vices) bounds its titles to the space between bars and is not affected.

## Evidence

- `lib/widgets/chart_text.dart:35` — `if (fits('$name$suffix') || !fits('…$suffix')) { return '$name$suffix'; }` returns the uncut title when the suffix alone does not fit.
- `lib/vice_chart.dart:239-245` — the width is `radarTitleWidth(constraints.biggest, vices.length, radarTitleOffset) - titleGap`, the chord between neighbouring titles, which falls as `vices.length` rises.
- `test/usage_graph_test.dart:326` — `'radar titles too many to fit any name are left whole'` asserts the fallback for 31 vices: `'Vice 31 (2 items)'`.
