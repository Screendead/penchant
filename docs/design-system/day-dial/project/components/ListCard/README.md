# ListCard

Cards of rows for the pages: the Habits list, a habit's history grouped by day, and Settings.

**Provide:** the rows, and for history the entries grouped by local day with each day's total.

- Card: `surface`, `radius-card`, 1px `line`, `shadow-card`. Dividers are 1px `line` starting after the leading mark.
- Section labels in `labelS` `muted` sit above cards ("Archived", "App").
- Habit row (66pt): a 14px pip (`dataN` with its `dataNRim` rim, or a `dataNInk` ring for a ring habit), the name in `bodyL`, then "drinks · 1,287 entries" in `bodyS` `muted`, and a `muted` chevron. Archived habits go in their own card under "Archived".
- Entry row (56pt): a 30px Bead, the time in `monoM`, and the amount right-aligned in Text 500 15px.
  - A day head above each group: "Today" and "4 drinks", both Text 600 13px `muted`, with the number in Mono.
  - Swipe left past 90pt to delete over a `danger` fill with a `surface` trash icon, then show the UndoBar. A tap opens the EntrySheet.
  - "Show older" (a secondary pill) loads 8 more days.
- Settings row (56pt): the label in Text 500 16px. On the right, the value in Text 14px `muted` with a chevron or share icon. Numbers are Mono ("0.2.0 (212)"). Sign out is its own card in `danger`.
- Footnotes in Text 12.5px `muted` explain a gesture or a rule ("Colours follow the order habits were added, archived ones included.").

**Do not** put toggles in Settings rows without a pattern for them, or show a delete button on rows. Delete is the swipe, or the EntrySheet.
