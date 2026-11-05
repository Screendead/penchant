# Chip

A habit picker in Trends: one pill per habit, one selected.

**Provide:** all habits in creation order, archived ones last, and the selected one.

- `size-chipHeight` tall, `radius-pill`, `surface2` at rest, `labelS`.
- A 10px pip leads the name (a ring pip for a ring habit). Archived habits add "· archived" in Text 500 `muted`.
- Selected: the fill is the habit's `dataN` at 18% over `surface`, with a 1.5px border in its `dataNInk`, so the border holds 3:1 in light.
- The row scrolls horizontally and fades out over its last 36pt.

**Do not** use chips for filters other than the habit, or allow more than one selected.
