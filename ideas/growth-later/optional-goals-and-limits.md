# Let a vice carry an optional goal, never a required one

**Priority:** growth / later

## What

Each vice can carry an optional goal: a direction (fewer, more, or none), and a daily or weekly limit. Where one is
set, its tile on Today shows progress, the check-in can nudge near it, and trends draw the line. With none set, the
app is purely a journal, and nothing anywhere suggests the user should have one.

## Why

- SOURCED (C15): cutting down "may coexist"; the journal is the point.
- SOURCED (C18): new optional fields on vices are allowed, so `goalDirection`, `limit` and `limitPeriod` need no
  further call.
- SOURCED (C5): a clean day is quietly positive, with no streak pressure; a goal must not bring streaks back.
- INFERENCE: some journal users will come wanting less of something; an optional limit costs little and keeps them.

## Options

- **A.** Daily or weekly limit per vice, set from the vice's settings, after 1.1.
- **B.** A in 1.0, offered in onboarding.
- **C.** No goals at all.

## Recommendation

Claude's recommendation: **A, after 1.1, free.** Offering it in onboarding (B) would frame the app as a reduction
tool, against C16. Never suggest a limit from public guidance: that pulls toward guideline 1.4.1's medical scrutiny.

**Effort:** M

**Revenue impact:** Low to medium: retention for the users who want it.

**Depends on:** [granular logging](../insights/granular-logging-and-data-model.md); [Today](../v1-must-haves/today-screen-rework.md).

**Needs Jack:** no
