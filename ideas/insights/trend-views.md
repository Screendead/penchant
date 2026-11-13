# Decide which trend views are Pro

**Priority:** insights (1.0 free, deeper views Pro)

## What

Every trend view is built free in the Trends sheet: daily and weekly totals with a moving average, stats, an
hour-of-day ring, an average week, Compare (up to three other habits), spend for a priced habit, a Health measure under
the habit line (iOS), and tagged entries by trigger area over time. Built free per Jack's 2026-11-08 "build it free
for me, we can paywall later". Left is only which of them a paywall would hold back.

## Why

- SOURCED (code): `TrendsSheet` (`lib/trends/`) buckets by day or by week, overlays a moving average and other
  habits, and draws when in the day and the week a habit happens, with the arithmetic in tested pure functions
  (`lib/data/usage_series.dart`).
- INFERENCE: descriptive views need no statistics gate and give a new user something on day three, long before the
  [insights engine](insights-engine.md) has 21 days.

## Options

- **A.** Descriptive views free; Compare, Health under the line and trigger areas Pro.
- **B.** All trend views free; only engine-backed insights Pro.
- **C.** All trend views Pro beyond 30 days.

## Recommendation

Claude's recommendation: **A.** A journal that hides your own history looks hostile (C17's "free 1.0" sets that
expectation), but overlays with Health are the visual teaser for the engine's cards.

**Effort:** S (a gate on built views)

**Revenue impact:** Medium: the free views drive retention; the overlays sell Pro.

**Depends on:**
- [business model](../monetisation/business-model-and-paywall.md)

**Needs Jack:** no
