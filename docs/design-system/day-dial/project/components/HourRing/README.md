# HourRing

When a habit happens: its entries over a range binned by hour round a small 24-hour ring.

**Provide:** the habit, its entries binned into 24 hours over the range (up to 90 days), and the busiest 3-hour window.

- The ring has a 100-unit viewBox, drawn at 96px in Trends and 92px in the history summary card. It has a `surface` disc (radius 47), a `line` circle at 26, and four `spoke` ticks at 00, 06, 12 and 18.
- Each hour with entries is a wedge from 26 out to 46 at the busiest hour, in the habit's `dataN` with a 1.25px `dataNRim` edge, which holds 3:1 on the disc in light. "24 h" sits at the centre in Display 700 9px `muted`.
- Copy beside it: "Mostly 07:00–10:00" in Text 600 14px, then "When coffee happens, over the last 30 days. 79% of it before noon." in `muted`. With nothing in range: "Nothing in this range" / "Entries show here by hour of day."
- In Trends it sits in a `surface2` panel (radius 22). On a history page it heads the page in a `surface` card, with "Last 30 days" and the total in Mono 24px.

**Do not** label hours on the ring. The sentence carries the reading.
