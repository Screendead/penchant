# Add crash reporting before TestFlight, and only content-free analytics

**Priority:** v1 must-have

## What

Add crash reporting before the first TestFlight build, so beta crashes are seen. Later, add a few content-free product
events: sign-up, first vice, first log, day-7 return, paywall shown, purchase. No event ever carries a vice name, a
quantity, a trigger, a note, or anything read from Health or Calendar.

## Why

- SOURCED (register): nothing is recorded on any platform; caught errors are shown once and discarded; a failed
  Firebase start leaves a blank screen.
- SOURCED ([Apple 5.1.3](https://developer.apple.com/app-store/review/guidelines/)): health data may not be used for
  advertising, marketing or data mining.
- INFERENCE: every SDK is a line in the privacy label, and "insights stay on your device" is a selling point. Pricing
  the Pro unlock needs conversion events.

## Options

- **A.** Firebase Crashlytics only.
- **B.** Crashlytics plus Google Analytics for Firebase with content-free events (check how to turn off ad-ID
  collection).
- **C.** Sentry plus a privacy-first analytics service (for example TelemetryDeck). Better story, another vendor.
- **D.** Nothing.

## Recommendation

Claude's recommendation: **A at TestFlight**, then content-free funnel events (B or C) when the paywall ships in 1.1,
the first time conversion data drives a decision.

**Effort:** S

**Revenue impact:** Indirect: crash-free sessions protect ratings, and funnel events later set the price.

**Depends on:**
- [`no-logging-crash-reporting-or-telemetry`](../../tech-debt/error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)
- [`firebase-bootstrap-has-no-error-handling`](../../tech-debt/error-handling-and-observability/firebase-bootstrap-has-no-error-handling.md)
- [`catch-sites-render-the-error-once-and-discard-it`](../../tech-debt/error-handling-and-observability/catch-sites-render-the-error-once-and-discard-it.md)
- [privacy policy](../release-blockers/privacy-policy-and-labels.md)

**Needs Jack:** yes — Crash reporting alone at launch, and how much product analytics can "on your device" carry later?
