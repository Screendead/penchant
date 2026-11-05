# AmountSheet

The bottom sheet for logging (or editing) an entry with a chosen amount and time.

**Provide:** the habit, the starting amount (its default or the entry's), the starting time (now or the entry's), the day, and that day's other entries for the ghost beads.

- Header: a 12px pip and the habit name (Display 700 20px), and a 36px `surface2` close circle.
- Stepper: two 56px `surface2` circles round the amount in `monoXL` over its unit (Text 500 14px `muted`). It steps by 1, or by 5 for habits whose typical amount is 10 or more. Minus is disabled at one step.
- Time: the mini DayDial (216px) with the day's other beads at 40%. Drag the knob (radius 11, `accent`, 3px `surface` stroke) round radius 112. It snaps to 5 minutes with a selection haptic per step, and on today it clamps to now.
- Under the dial: "Now · drag the hand to change the time", or "2 h 40 min ago · **Now**" once moved (Now resets it). A past day shows its date.
- Action: one primary button stating the result, "Log 2 drinks at 18:30" (or "Save …" when editing), with the numbers in Mono.
- Editing reuses this sheet. On save the bead travels round the rim to its new time.

**Do not** bring back separate date and time pickers, a lock toggle or a seconds ticker.
