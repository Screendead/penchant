# EntrySheet

The bottom sheet for one entry, opened from its bead or its history row.

**Provide:** the entry (habit, quantity, unit, time, day, pending).

- Header: a 12px pip and the habit name (Display 700 20px), and a 36px `surface2` close circle.
- Body: the amount in `monoXL` with its unit (Text 500 16px `muted`). Below it, the meta line in Text 14px `muted`: "at 19:30 · Today, Thu 5 Nov", ending "· not yet synced" while pending.
- Actions: two equal 46px tonal buttons. Edit (pencil) opens the AmountSheet. Delete (trash, `danger` on `dangerContainer`) removes the entry at once and shows the UndoBar.

**Do not** ask "Are you sure?" The 8-second Undo is the safety net.
