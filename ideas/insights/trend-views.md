# Show the journal's trends: Health under the habit lines, triggers and spend

**Priority:** insights (1.0 free, deeper views Pro)

## What

Grow the Trends sheet (overhaul step 1c, which replaced the Graph tab):

- **Shipped in the Trends sheet, free:** each vice's daily and weekly totals over a range with a moving average, its
  stats, an hour-of-day ring, an hour-of-day × weekday grid, and up to three other vices overlaid on one time axis
  (Compare). Built free per Jack's 2026-11-08 "build it free for me, we can paywall later"; the overlays are the Pro
  candidate if a paywall comes.
- **Still to come (Pro in 1.1):** Health outcomes drawn under the vice lines (for example nightly HRV under evening
  drinks), trigger breakdowns over time, and spend.

## Why

- SOURCED (code): `TrendsSheet` (`lib/trends/`) buckets by day or by week, overlays a moving average and other
  habits, and draws when in the day and the week a habit happens, with the arithmetic in tested pure functions
  (`lib/data/usage_series.dart`).
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
