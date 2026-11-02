# Rebuild Today around progress cards, and keep the radar as an optional view

**Priority:** v1 must-have

## What

Make Today a list of per-vice cards. Each card shows today's count, progress against the limit, a quick-log button and a 7-day sparkline. Add a week/month heatmap of free days against over-limit days. Changing days becomes a swipe, or a tap on a heatmap cell. The radar becomes a secondary "balance" toggle that appears only at three or more vices.

A day with nothing logged shows a calm card ("Nothing logged: a free day"), never red. The headline metric is a rolling count, for example "5 of the last 7 days free". A streak appears only for vices with a "quit" goal.

## Why

- SOURCED (code): fl_chart 1.2.0 asserts at least 3 radar entries (`radar_chart_data.dart:298`), and `lib/vice_chart.dart` builds one entry per unarchived vice name while guarding only the zero-vice and zero-activity cases. A user with one or two vices gets a broken chart. The register does not list this.
- SOURCED (register): the radar has no screen-reader semantics, ignores text scale and merges vices that share a name. A zero day renders as an error in the error colour, and the day picker can freeze.
- INFERENCE: a strict streak that resets on one slip is a known reason people quit sobriety apps. A calendar filling with free days motivates without reading as a "high score" (1.4.3).

## Options

- **A.** Cards and heatmap by default, with the radar as an optional view at three or more vices.
- **B.** Keep the radar as the hero and fix its bugs.
- **C.** Drop the radar entirely.

## Recommendation

Claude's recommendation, not a decision: **A.** The radar is the one visual the market scan found no competitor using, so keep it for multi-vice users rather than delete it. Build the new screen to be accessible from the start: a text summary for each chart, Dynamic Type up to the largest sizes, and VoiceOver passes in the e2e run. That clears most of the accessibility cluster without a retrofit. Show Jack a mock-up before building.

**Effort:** L

**Revenue impact:** Medium. It improves the first impression and the store screenshots. Heatmap depth beyond 30 days is a natural Pro hook.

**Depends on:**
- [quick logging](one-tap-quick-logging.md)
- [per-vice goals](per-vice-goals-and-limits.md)
- [`charts-carry-no-screen-reader-semantics`](../../tech-debt/accessibility-and-localization/charts-carry-no-screen-reader-semantics.md)
- [`radar-data-is-keyed-by-vice-name`](../../tech-debt/widget-state-and-view-logic/radar-data-is-keyed-by-vice-name.md)
- [`a-zero-activity-day-renders-as-an-error`](../../tech-debt/navigation-and-unreachable-ui/a-zero-activity-day-renders-as-an-error.md)
- [`date-navigation-awaits-a-future-that-never-completes`](../../tech-debt/widget-state-and-view-logic/date-navigation-awaits-a-future-that-never-completes.md)
- [`radar-chart-text-ignores-system-text-scale`](../../tech-debt/accessibility-and-localization/radar-chart-text-ignores-system-text-scale.md)

**Needs Jack:** yes — Should the radar stay the hero, or move to a secondary view behind cards? He decides from a mock-up.
