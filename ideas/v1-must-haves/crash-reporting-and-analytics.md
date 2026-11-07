# Add only content-free product analytics, if any

**Priority:** v1 must-have

## What

Crash reporting shipped as Firebase Crashlytics (Jack's pick A, 2026-11-06, no analytics at launch). What is left is
whether a later release adds a few content-free product events: sign-up, first habit, first log, day-7 return, paywall
shown, purchase. No event would ever carry a habit name, an amount, a trigger, a note, or anything read from Health or
Calendar.

## Why

- SOURCED ([Apple 5.1.3](https://developer.apple.com/app-store/review/guidelines/)): health data may not be used for
  advertising, marketing or data mining.
- INFERENCE: every SDK is a line in the privacy label, and "insights stay on your device" is a selling point. Pricing
  the Pro unlock needs conversion events.

## Options

- **A.** Google Analytics for Firebase with content-free events (check how to turn off ad-ID collection).
- **B.** A privacy-first analytics service (for example TelemetryDeck). Better story, another vendor.
- **C.** Nothing.

## Recommendation

Claude's recommendation: decide when the paywall ships in 1.1, the first time conversion data drives a decision.

**Effort:** S

**Revenue impact:** Indirect: funnel events set the price.

**Depends on:**
- [privacy policy](../release-blockers/privacy-policy-and-labels.md)

**Needs Jack:** yes, at 1.1 — how much product analytics can "on your device" carry?
