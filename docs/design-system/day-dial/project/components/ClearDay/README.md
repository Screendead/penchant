# ClearDay

The dial's state for a day with no entries: a calm sage ring in place of beads.

**Provide:** whether the day is today.

- Dim the spokes to 25%. Lay a 16px `clear` band at radius 116, then draw a 2px `clearInk` ring at 60% on it.
- The hub reads "A clear day" over "so far" (today) or "nothing logged" (a past day), in `clearInk`, Text 600 at 12.5px.
- Today keeps its now-hand and elapsed arc.
- Motion: the ring draws on clockwise from 00 over 600 ms (`easeInOutCubic`) as the spokes fade. Logging the first entry reverses it.

**Do not** call it empty, missing or a streak, and do not show it while the day's entries are still loading.
