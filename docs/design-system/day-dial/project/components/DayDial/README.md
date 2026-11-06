# DayDial

The Today chart: one day as a 24-hour clock face, with each entry as a bead at the time it happened.

**Provide:** the day's entries, each with a habit, a quantity and a `createdAt`; each habit's colour index and typical quantity; whether the day is today; the current time.

**Use it** as the first thing on Today, at `size-dial`, centred in the gutter. Reuse the face for the amount sheet's mini dial (216px) and for a day opened from Trends (300px, disc `surface2`, hub `surface`).

- Follow the geometry in the brand book's Day Dial section exactly. Spokes, numerals, hub, hand and bead tracks all have fixed radii.
- Today only: draw the now-hand and the elapsed arc, and show the clock in the hub. A past day shows its weekday there.
- The hub's second line counts entries ("1 entry", "15 entries") in `bodyS` `muted`.
- At 4 entries or fewer, label each bead with its time (`dialTime`, `muted`, haloed in `surface`). Above that, show no labels.
- Make each bead a button that opens its EntrySheet. Make the dial itself one labelled node with the day summary.
- Swiping the dial sideways changes the day, as the DayPicker arrows do, using the contract and sweep motion.
- With no entries, show ClearDay.

**Do not** reorder, cluster or nudge beads off their time except along the arc. Do not add gridlines, a legend or a total to the face. Do not use a habit colour anywhere but the beads.
