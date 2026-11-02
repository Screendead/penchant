# Harden the backend before strangers can install the app

**Priority:** release blocker

## What

Before any stranger can install the app, the backend needs five things:

- close the cross-account write hole;
- validate fields and types in the rules;
- bound or paginate every list query;
- add the missing composite index;
- cover the rules with emulator tests that run in CI.

Then turn on Firebase App Check: monitor mode first, enforcement after.

## Why

- SOURCED (register): a user can overwrite and reassign another account's document. Writes carry no field validation. The main chart's query has no matching index. Every list streams unbounded data. The rules and indexes are never tested.
- INFERENCE: once installs are public, a rules hole is a data breach. The market scan has an unverified report of a Reframe breach, which shows the stakes for a privacy-positioned app.

## Options

- **A.** Rules fixes plus emulator rules tests only.
- **B.** A, plus App Check: App Attest or DeviceCheck on iOS, Play Integrity on Android, reCAPTCHA on web. Verify the current Flutter setup in the Firebase docs.
- **C.** B, plus budget alerts and per-user write-rate limits in the rules.

## Recommendation

Claude's recommendation, not a decision: **B**, plus the budget alerts from C, which cost nothing. Agents write and emulator-test the rules and the client App Check wiring. Turning on enforcement and setting budgets are production console actions that Jack performs. They are tasks for him, not decisions.

**Effort:** M

**Revenue impact:** Avoids risk. A breach or a runaway Firestore bill would end a privacy-positioned app.

**Depends on:**
- [`write-rules-authorize-on-the-post-write-owner`](../../tech-debt/firebase-data-layer/write-rules-authorize-on-the-post-write-owner.md)
- [`writes-carry-no-field-or-type-validation`](../../tech-debt/firebase-data-layer/writes-carry-no-field-or-type-validation.md)
- [`unarchived-vices-query-has-no-matching-index`](../../tech-debt/firebase-data-layer/unarchived-vices-query-has-no-matching-index.md)
- [`no-query-is-bounded-or-paginated`](../../tech-debt/firebase-data-layer/no-query-is-bounded-or-paginated.md)
- [`rules-and-indexes-are-never-deployed-or-tested`](../../tech-debt/firebase-data-layer/rules-and-indexes-are-never-deployed-or-tested.md)
- [`every-firebase-command-targets-production`](../../tech-debt/firebase-data-layer/every-firebase-command-targets-production.md)

**Needs Jack:** no
