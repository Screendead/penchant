# Menu

The popover from the app bar's wordmark: the way to Habits and Settings, with the sync summary.

**Provide:** the sync state and the time of the last sync.

- A 244pt `surface` card at `radius-card` with a 1px `line`, `shadow-pop` and 8pt padding, hung 4pt under the wordmark.
- Items are 12pt-padded rows with radius 16: a 20px `muted` icon (grid for Habits, gear for Settings) and Text 500 15.5px. Hover or press fills them `surface2`.
- A 1px `line` divider, then the footer: cloudok and "All entries synced · last at 21:08" in Text 12.5px `muted`, with the time in Mono.
- It opens on a spring from 0.86 scale at its top-left corner, and closes over 140 ms.

**Do not** add destructive items here. Sign out lives in Settings.
