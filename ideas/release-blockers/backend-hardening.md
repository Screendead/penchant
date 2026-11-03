# Harden the backend before strangers can install the app

**Priority:** release blocker

## What

The rules rewrite (PR #27) is live in production since 2026-11-03, with 55 emulator tests in CI, and queue item 1b
adds the quantity, name-length and vice-ownership checks. What is left before strangers install:

- bound or paginate every list query;
- turn on Firebase App Check (App Attest on iOS and macOS), monitor mode first, enforcement after;
- budget alerts on the production project.

Health and calendar data never reach Firestore (see the [insights engine](../insights/insights-engine.md)), so the
backend holds only the user's own logs.

## Why

- SOURCED (register): every list query streams unbounded data, which grows the read bill and the cold-start time
  with every year of history a journal user builds.
- INFERENCE: a privacy-positioned journal survives a bug, not a breach or a runaway bill.

## Options

- **A.** Bounded queries only.
- **B.** A, plus App Check. Read the current Firebase App Check docs for Flutter on Apple platforms first.
- **C.** B, plus per-user write-rate limits in the rules.

## Recommendation

Claude's recommendation: **B**, plus budget alerts, which cost nothing. Agents write the queries and the client App
Check wiring and test them on the emulators. Turning on enforcement and setting budgets are production console actions
for Jack: tasks, not decisions.

**Effort:** M

**Revenue impact:** Avoids risk.

**Depends on:**
- [`no-query-is-bounded-or-paginated`](../../tech-debt/firebase-data-layer/no-query-is-bounded-or-paginated.md)
- [`wherein-filter-is-unbounded-and-includes-archived`](../../tech-debt/firebase-data-layer/wherein-filter-is-unbounded-and-includes-archived.md)
- [`vice-activity-relationship-is-unenforced`](../../tech-debt/firebase-data-layer/vice-activity-relationship-is-unenforced.md) (queue 1b)

**Needs Jack:** no
