# Make Today a journal of the day: a timeline, per-vice tiles and the chart

**Priority:** v1 must-have

## What

Today becomes the day's journal page:

- per-vice tiles with today's total and a 7-day sparkline, which double as [quick-log](one-tap-quick-logging.md)
  buttons;
- a timeline of today's entries, each with its time, quantity, triggers and note, tappable to edit;
- the day chart: bars below three vices and the radar from three up (C2, built in queue 1a);
- a day with nothing logged looks quietly positive, with a green tint and short encouraging copy and no streak (C5,
  built in queue 1a).

Swiping changes the day. A goal's progress shows on a tile only if the user set an
[optional goal](../growth-later/optional-goals-and-limits.md).

## Decision

Decided by Jack 2026-11-05 (`r6-ui-direction`): **the Day Dial**, a 24-hour dial with each entry a bead at its time,
tally rows with a one-tap `+` each, and a Log button with a fan of habits. It supersedes C2 (bars below three vices,
the radar from three up): the radar leaves Today. C5 stands: **a clean day is quietly positive**, now a sage ring and
"A clear day so far". The mock-up and its Flutter notes are on `origin/design/ui-overhaul-day-dial`; the build is
HANDOVER's queue item 1.

## Why

- INFERENCE: for a journal the useful unit is the entry, not the daily total. A timeline shows when and why, which is
  what the insights are built on, and it is where users notice and fix a wrong entry.
- SOURCED (register): the charts have no screen-reader semantics and ignore text scale.

## Options

- **A.** Tiles, timeline and chart, as above.
- **B.** Keep today's chart-first screen and add the timeline below it.
- **C.** Timeline only, with the chart moved to the trends tab.

## Recommendation

Claude's recommendation: **A**, built accessible from the start: a text summary for each chart, Dynamic Type at the
largest sizes, VoiceOver checks in the e2e run. Show Jack a mock-up first.

**Effort:** L

**Revenue impact:** Medium: first impression and store screenshots.

**Depends on:**
- [quick logging](one-tap-quick-logging.md)
- [`charts-carry-no-screen-reader-semantics`](../../tech-debt/accessibility-and-localization/charts-carry-no-screen-reader-semantics.md)
- [`radar-chart-text-ignores-system-text-scale`](../../tech-debt/accessibility-and-localization/radar-chart-text-ignores-system-text-scale.md)

**Needs Jack:** no — the layout is decided (`r6-ui-direction`).
