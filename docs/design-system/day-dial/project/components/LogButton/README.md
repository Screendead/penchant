# LogButton

The one primary action on Today: a 64pt ink circle that opens a fan of the habits to log.

**Provide:** the unarchived habits in creation order, with each one's default amount and unit.

- It is `size-logButton`, `accent` with an `onAccent` 28px plus and `shadow-logButton`. It docks centred on the Trends sheet's top edge and fades as the sheet rises.
- A tap opens the fan over a `scrim` with a 6px backdrop blur. The fan is pentagon wedges round a centre 157pt above the button, from radius 44 to 152, at most 8 per ring with "More" beyond.
- Each wedge is its habit's `dataN` with a 1.25px `dataNRim` inner rim, separated by a 3px `bg` stroke. In light the rim holds 3:1 against the gap and the scrim. It carries the name (Text 600 12.5px) and "+1 drink" (Mono 11px), both in `wedgeInk`.
- The hub shows the time (Mono 15px) over "now". A surface pill above reads "**Tap** to log now · **hold** for amount and time".
- Tap a wedge to log its default amount now. Hold one for 400 ms to open the AmountSheet. Or press the button, drag and release on a wedge.
- When open, the button turns `surface` with a `text` × (the plus turned 45°).
- First run only: a "Tap Log" coach pill (`text` fill, `bg` label) beside a pulsing ring.
- Wedges are `CustomSemanticsAction`s on the button.

**Do not** add a second floating button, recolour the button with a habit, or put any text other than `wedgeInk` on a wedge.
