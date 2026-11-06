# Show the journal's trends: time of day, weekday, and vices side by side

**Priority:** insights (1.0 free, deeper views Pro)

## What

Grow the Trends sheet (overhaul step 1c, which replaced the Graph tab):

- **Free in 1.0:** each vice's daily and weekly totals over a range with a moving average, its stats and an
  hour-of-day ring (shipped in the Trends sheet), and still to come an hour-of-day × weekday heatmap per vice.
- **Pro in 1.1:** several vices overlaid on one time axis, Health outcomes drawn under the vice lines (for example
  nightly HRV under evening drinks), trigger breakdowns over time, and spend.

## Why

- SOURCED (code): `TrendsSheet` (`lib/trends/`) buckets by day or by week, overlays a moving average and draws when
  in the day a habit happens, with the arithmetic in tested pure functions (`lib/data/usage_series.dart`).
- INFERENCE: descriptive views need no statistics gate and give a new user something on day three, long before the
  [insights engine](insights-engine.md) has 21 days.

## Options

- **A.** As above: descriptive views free, overlays and Health Pro.
- **B.** All trend views free; only engine-backed insights Pro.
- **C.** All trend views Pro beyond 30 days.

## Recommendation

Claude's recommendation: **A.** A journal that hides your own history looks hostile (C17's "free 1.0" sets that
expectation), but overlays with Health are the visual teaser for the engine's cards.

**Effort:** M

**Revenue impact:** Medium: the free views drive retention; the overlays sell Pro.

**Depends on:**
- [business model](../monetisation/business-model-and-paywall.md)

**Needs Jack:** no
