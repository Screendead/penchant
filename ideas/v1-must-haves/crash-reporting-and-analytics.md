# Add crash reporting before TestFlight, and only content-free analytics

**Priority:** v1 must-have

## What

Add crash reporting before the first TestFlight build, so that beta crashes are seen. Later, add a small set of product events: sign-up, first vice, first log, day-7 return, paywall shown and purchase. No event may ever carry a vice name, a quantity or any other log content.

## Why

- SOURCED (register):
  - Nothing is recorded on any platform.
  - Caught errors are shown once and then discarded.
  - A failed Firebase start leaves a blank screen.
- SOURCED ([Apple 5.1.3](https://developer.apple.com/app-store/review/guidelines/)): health data must not be used for advertising or data mining.
- INFERENCE: every SDK becomes a line in the privacy label, which weighs against the "private" positioning. Pricing cannot be tuned without conversion events.

## Options

- **A.** Firebase Crashlytics only. Already inside the Firebase vendor, and a small label impact.
- **B.** Crashlytics plus Google Analytics for Firebase with content-free events. Verify the configuration that turns off ad-ID collection.
- **C.** Sentry plus a privacy-first analytics service (for example TelemetryDeck). A better privacy story, but another vendor.
- **D.** Nothing. You fly blind in beta.

## Recommendation

Claude's recommendation, not a decision: **A at TestFlight.** Add content-free funnel events (B or C) only when the paywall ships, because that is the first time conversion data drives a decision.

**Effort:** S

**Revenue impact:** Indirect. Crash-free sessions protect ratings, and the funnel events later set prices.

**Depends on:**
- [`no-logging-crash-reporting-or-telemetry`](../../tech-debt/error-handling-and-observability/no-logging-crash-reporting-or-telemetry.md)
- [`firebase-bootstrap-has-no-error-handling`](../../tech-debt/error-handling-and-observability/firebase-bootstrap-has-no-error-handling.md)
- [`catch-sites-render-the-error-once-and-discard-it`](../../tech-debt/error-handling-and-observability/catch-sites-render-the-error-once-and-discard-it.md)
- [privacy policy](../release-blockers/privacy-policy-and-labels.md)

**Needs Jack:** yes — Is crash reporting alone acceptable at launch, and how much product analytics can the privacy positioning carry later?
