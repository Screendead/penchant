# UndoBar

The snackbar that confirms a log, an edit or a delete, with Undo for 8 seconds.

**Provide:** the message (habit, amount and time in bold) and, where it can be undone, the undo action.

- An inverted pill, at least 52pt tall: `text` fill, `bg` copy in Text 500 14px, bold parts at 600. It floats 46pt above the Trends sheet's edge, inset `space-m`.
- Undo is a 40pt pill (`bg` at 14% over the bar) with a 20px countdown ring that empties linearly over 8000 ms, then the word "Undo".
- A bar without Undo ("Entry restored", "Entry removed", "Entry updated: 2 drinks at 18:30") leaves after 3 s.
- It springs up from 20pt below. Under reduce motion it fades in over 150 ms. It is a polite live region.

Copy: "Logged **1 drink** of Alcohol at **21:10**", "Deleted **2 drinks** of Alcohol", "Saved on this device. It will sync when you're back online."

**Do not** stack bars. A new one replaces the last.
