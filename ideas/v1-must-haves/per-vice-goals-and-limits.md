# Give each vice a goal and a limit, so Today can say "on track"

**Priority:** v1 must-have

## What

Each vice gets an optional goal with three parts:

- **Direction:** reduce, quit or just track.
- **Limit:** daily or weekly, for example 14 drinks a week or 2 coffees a day.
- **Baseline:** an optional figure captured at setup.

Today shows progress against the limit, and the radar is drawn relative to it. The goal is stored as new optional fields on `vices`, with rules validation, and a parser that treats a missing field as "no goal".

## Why

- INFERENCE: without a goal the app only records. With one it can say "you're on track", which is what users come back to check. Goals also drive the free-day metrics, reminders ("1 left today") and insights ("down 30% against your baseline").
- SOURCED ([market scan](../market-scan.md)): Reframe and Sunnyside charge $8–25 a month, in that class, for reduction tooling.
- SOURCED (code): `Vice.fromJson` casts every field unconditionally (`json['archived'] as bool`, `lib/data/vice.dart:31`). A new field must therefore be read as nullable, or every existing document throws.
- Standing rule: the documented Firestore shape must stay. Whether an additive optional field counts as keeping it is Jack's call.

## Options

- **A.** A daily limit only.
- **B.** A daily or weekly limit chosen per vice, with direction and baseline.
- **C.** Limits suggested from public guidance, for example the UK's 14 units a week.

## Recommendation

Claude's recommendation, not a decision: **B.** Weekly limits suit alcohol and gambling, and daily limits suit caffeine and nicotine. Setting a limit stays free, because it is the harm-reduction behaviour reviewers want to see. The history of days within the limit is the paid part (see the [business model](../monetisation/business-model-and-paywall.md)). Skip C: quoting health guidance pulls the app towards 1.4.1 medical scrutiny. Read the Firebase rules docs before the schema change, and test it on the emulators.

**Effort:** M

**Revenue impact:** High. It is the clearest "worth paying for" anchor.

**Depends on:**
- [positioning](../release-blockers/positioning-and-target-user.md)
- [`model-parsers-cast-unconditionally`](../../tech-debt/firebase-data-layer/model-parsers-cast-unconditionally.md)
- [`writes-carry-no-field-or-type-validation`](../../tech-debt/firebase-data-layer/writes-carry-no-field-or-type-validation.md)

**Needs Jack:** yes — May new optional fields be added to `vices` (here goal, limit and baseline) under the rule that the data shape must stay?
