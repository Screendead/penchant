# Get a new user from install to a first log in under a minute

**Priority:** v1 must-have

## What

Replace today's first run, where a zero-vice account sees an endless spinner, with three skippable steps:

1. A one-line explanation of the app.
2. One-tap starter vices, each preset with the right unit, plus a "custom" option.
3. An optional limit per vice.

The flow ends on Today with the first log in place. Ask for notification permission only if the user picks a reminder time.

## Why

- SOURCED (register): a zero-vice account loads forever, an ordinary zero-activity day renders as an error, and Manage Data hides its add-vice button when there are no activities.
- SOURCED (code): fl_chart 1.2.0 asserts `'Radar needs at least 3 RadarEntry'` (`radar_chart_data.dart:298`). `lib/vice_chart.dart` guards the zero-vice case only, so one or two vices trip the assert in debug builds and draw a degenerate chart in release. The register does not list this.
- SOURCED (code): `Unit` already covers item, time, puff, drink, minute and hour, so the presets need no schema change.
- INFERENCE: App Review and every new user see this flow first.

## Options

- **A.** An "Add your first vice" call to action on the empty Today screen, and nothing more.
- **B.** A, plus the preset picker and the optional limit step (for example Alcohol/drinks, Coffee/items, Cigarettes/items, Vape/puffs, Screen time/minutes, Custom).
- **C.** B, plus a three-screen intro carousel.

## Recommendation

Claude's recommendation, not a decision: **B**, starting as a guest. Presets get users to a meaningful Today screen in seconds. Skip the carousel, because those are usually skipped (INFERENCE). Use non-judgemental copy, for example "What would you like to keep an eye on?".

**Effort:** M

**Revenue impact:** High. The activation rate multiplies every later conversion number.

**Depends on:**
- [guest mode](guest-mode-and-sign-in.md)
- [per-vice goals](per-vice-goals-and-limits.md)
- [Today rework](today-screen-rework.md)
- [substance framing](../release-blockers/substance-framing-and-age-rating.md)
- [`empty-stream-shortcircuit-reads-as-permanent-loading`](../../tech-debt/widget-state-and-view-logic/empty-stream-shortcircuit-reads-as-permanent-loading.md)
- [`a-zero-activity-day-renders-as-an-error`](../../tech-debt/navigation-and-unreachable-ui/a-zero-activity-day-renders-as-an-error.md)
- [`manage-data-hides-everything-when-activities-are-empty`](../../tech-debt/navigation-and-unreachable-ui/manage-data-hides-everything-when-activities-are-empty.md)

**Needs Jack:** yes — Which substances go in the preset list, and how are they worded? Naming substances is a tone and 1.4.3 question.
