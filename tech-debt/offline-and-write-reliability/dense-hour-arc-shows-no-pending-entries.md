# A dense hour's arc does not show which of its entries are unsynced

**Severity:** low

On a day of more than 48 entries, an hour holding more than one entry is drawn as one arc. A pending bead has a
hollow, turning rim until the server acknowledges it; the arc paints its habits' shares the same whether or not any
entry in it is pending, so an entry logged offline into a busy hour looks synced on the dial. The day's pending note
under the dial and the arc's screen-reader label ("N not yet synced") still say it.

## Evidence (at `feat/dense-hour-arc`, 2026-11-08)

- `lib/widgets/day_dial.dart:1337` — `pending: b.entry.pending,` (beads pass it to the painter)
- `lib/widgets/day_dial.dart:1372` — `paintHabitBand(canvas, pieces[i], shares[i].mark, colors);` (arcs pass nothing)
