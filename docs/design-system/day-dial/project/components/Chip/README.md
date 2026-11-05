# Chip

A habit picker in Trends: one pill per habit, one selected.

**Provide:** all habits in creation order, archived ones last, and the selected one.

- `size-chipHeight` tall, `radius-pill`, `surface2` at rest, `labelS`.
- A 10px pip leads the name: `dataN` with its 1.25px `dataNRim` rim, or for a ring habit a 2.2px ring in `dataNInk`. Archived habits add "· archived" in Text 500 `muted`.
- Selected: the fill is the habit's `dataN` at 18% over `surface`, with a 1.5px border in its `dataNInk`, which holds 4.6:1 or better against the sheet and 4.3:1 against its own tint.
- The row scrolls horizontally and fades out over its last 36pt.

**Do not** use chips for filters other than the habit, or allow more than one selected.
