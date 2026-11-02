# Position the app as a multi-substance moderation logger

**Priority:** release blocker

## What

Decide who 1.0 is for, and how the store listing frames it. The code already supports any number of vices, each with a unit (`lib/data/unit.dart`: item, time, puff, drink, minute, hour), and a radar chart that shows all of them for one day. Every later choice depends on this one: onboarding presets, units, tone, the price anchor and the store keywords.

## Why

- SOURCED ([market scan](../market-scan.md)): Reframe, Sunnyside and MyDrinkaware cover alcohol only. I Am Sober and Quitzilla count days abstinent rather than quantity.
- INFERENCE: the scan found no mainstream app that logs quantities across several substances with a radar view. The search was not exhaustive.
- SOURCED: the category's top review complaints are aggressive paywalls, trials that convert to annual plans unexpectedly, and hard-to-reach support. "Private data, honest billing, works offline" is the positioning those complaints leave open.

## Options

- **A. Multi-substance moderation:** "track and cut down on several habits at once". Harm-reduction tone, no abstinence requirement.
- **B. Alcohol-only moderation**, competing with Reframe, Sunnyside and MyDrinkaware on price and privacy.
- **C. Quit/streak counter**, competing with I Am Sober and Quitzilla.
- **D. Neutral consumption journal**, with no reduction framing at all.

## Recommendation

Claude's recommendation, not a decision: **A.** It is the only position without an obvious incumbent, and it matches what the data model already does (a quantity per vice per day). The radar and per-vice units only make sense across several substances. Moderation is also the safest reading of App Store guideline 1.4.3 (see [substance framing](substance-framing-and-age-rating.md)). The store copy should lead on privacy and honest billing.

**Effort:** S (a decision, plus copy)

**Revenue impact:** Indirect but foundational. It sets the market size and the price anchor: alcohol-only apps charge in the $8–25/month class, generic trackers $2–5/month (indicative, from the [market scan](../market-scan.md)).

**Depends on:** nothing.

**Needs Jack:** yes — Is 1.0 a multi-substance moderation logger (A), or one of alcohol-only, quit counter or neutral journal?
