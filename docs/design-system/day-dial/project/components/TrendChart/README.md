# TrendChart

One habit over a date range: three stat tiles, the raw series with its moving average, a readout and the average stepper.

**Provide:** the series by day or by week, its moving average, the window length, and the selected point (default the newest).

- Stats: three `surface2` tiles at `radius-tile`, for Total (with unit and "last 30 days"), Average ("per day" or "per week") and Peak (with its date or "week to 24 Sep"). Labels 11.5px `muted`, values `monoL`.
- Chart (236pt tall): gridlines in `line` at a round step (1, 2, 2.5 or 5 × 10ⁿ, at most 4 steps) with `monoS` labels in `muted`. Four date labels ending "Today".
  - The raw series is `dataN` 1.5px at 50%, with dots at 31 points or fewer.
  - The average is a curved 3px `dataNInk` line over a 10% `dataN` area.
  - The selected point has a cursor line (`text` at 25%), a raw dot ringed in `surface`, and an average dot in `surface` ringed in `dataNInk`.
- Readout: a `surface2` pill over the cursor, clamped inside the chart: "Today **5 drinks** avg **3.3**".
- Average stepper: a `surface2` pill reading "Average over **7** days" (or "No average line" at 1), with two 34pt circles (`surface`, `shadow-tiny`).
- Morph between ranges by resampling both series to a fixed count, 450 ms `easeInOutCubic`. Tapping a day point opens that day's dial in a container transform.

**Do not** use bars, stack habits on one chart, or colour the axes.
