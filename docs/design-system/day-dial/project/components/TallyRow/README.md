# TallyRow

One habit's total for the shown day, under the dial, with a + that logs its default amount.

**Provide:** the habit (name, colour index, unit), the day's total, and its default quantity for the + action.

- Each row is `size-tallyRow` tall: a 10px pip (`dataN` with its `dataNRim` rim), the name in `bodyL`, the total in `monoM` `dataNInk`, the unit in `bodyS` `muted` (min width 58), and the + button.
- The + is drawn at `size-tallyPlus` (`surface`, 1px `line`, a 16px plus) and hit at `size-hitArea`. It logs the habit's default amount now, with the UndoBar.
- List every unarchived habit in creation order, zeros included. A zero row sets its name and number in `muted`; its pip stays at full strength.
- On a log, roll the number over 300 ms and flash the row with its `dataN` at 16% for 700 ms.
- The + is the list path for VoiceOver and Switch Control. Label it "Log 1 drink of Coffee".

**Do not** sort by total, hide zero rows, or colour the name. Only the number takes the habit's ink.
