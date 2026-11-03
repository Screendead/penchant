# Get a new user from install to a first log in under a minute

**Priority:** v1 must-have

## What

Replace today's first run, where a new account lands on "No vices yet. Add one from Manage Data in the menu.", with three skippable steps:

1. One line on what the app is: a private journal that shows what goes with your habits.
2. One-tap starter vices, each with the right unit, plus "custom".
3. The disclaimer (C16), acknowledged once.

It ends on Today with the first log in place. Health, Calendar and notification permissions are never asked here:
each is asked the first time the user turns on the feature that needs it, with a screen that says what is read and
that it stays on the device.

## Why

- SOURCED (code): `lib/vice_chart.dart` sends a new user to Manage Data, two screens away, to create the first vice.
- SOURCED (code): `Unit` already covers item, time, puff, drink, minute and hour, so presets need no schema change.
- INFERENCE: a permission asked before the user knows what it buys is usually refused, and a refused HealthKit read
  cannot be detected by the app (see [Apple Health](../insights/apple-health-correlation.md)), so asking late matters.

## Options

- **A.** An "Add your first vice" call to action on the empty Today, and nothing more.
- **B.** A, plus the preset picker and the disclaimer step.
- **C.** B, plus an intro carousel.

## Recommendation

Claude's recommendation: **B**, starting as a guest. Neutral copy: "What would you like to keep a journal of?" Skip
the carousel (INFERENCE: usually skipped).

**Effort:** M

**Revenue impact:** High: activation multiplies every later conversion.

**Depends on:**
- [guest mode](guest-mode-and-sign-in.md)
- [neutral framing](../release-blockers/neutral-framing-and-age-rating.md)

**Needs Jack:** yes — Which presets, worded how? Naming substances is a tone and guideline 1.4.3 question.
