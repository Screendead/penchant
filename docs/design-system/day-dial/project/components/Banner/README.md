# Banner

Pills that drop from the top for offline mode and for writes the server refused.

**Provide:** offline (boolean), and the list of refused changes, each named at write time with its reason.

- Pills sit `space-m` in from the edges below the status bar, stacked 8pt apart. Each is radius 22, `surface` with a 1px `line` and `shadow-pop`, Text 500 13.5px, with an 18px leading icon.
- Offline: cloudoff, "Offline. New entries save on this device." A status live region.
- Refused: `dangerContainer` with a `danger` 30% border and a `danger` alert icon, "1 change was not saved" and a `muted` chevron. A tap expands it in place to the detail: "**Not saved: 2 drinks of Alcohol on Thu 5 Nov at 19:30**", "The habit was removed on another device.", and a `danger` "Dismiss". An alert live region.
- They drop in on a spring (about 260 ms) and lift away over 220 ms.

**Do not** auto-dismiss a refused write; it stays until dismissed. Do not use a banner for a successful action (that is the UndoBar).
