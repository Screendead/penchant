# TrendsSheet

The draggable sheet over Today that holds Trends, peeking at 15% with a sparkline.

**Provide:** the selected habit and range, and the series for the peek.

- Peek (15% of the height): the grab handle; "Trends" in Display 700 15px over "Coffee · last 30 days" in `muted`; on the right the daily average in Mono 17px `dataNInk` over "drinks a day"; then a 44pt sparkline (raw series dashed 1.5px in `dataNInk`, 7-day average solid 2.5px in `dataNInk`).
- Open (92%): "Trends" in `displayL` with a down-chevron circle to close. Below it: the habit Chips (scrolling, faded at the right edge), a row of two small SegmentedControls (range 7D / 30D / 90D / 1Y, step Day / Week), then the TrendChart and the HourRing. It ends with "Drag across the chart to read a day. Tap a day to open its dial."
- It snaps between the two sizes on a spring carrying release velocity. `scrim` dims Today as it rises, and the app bar and Log button fade.

**Do not** add dropdowns or a "buckets" slider. Chips and segments replace them.
