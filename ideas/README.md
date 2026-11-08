# Product ideas backlog

What is worth building between today's app and a paid release, as of 2026-11-03, for the positioning Jack chose: a
neutral journal for seeing trends and learning about yourself (C15–C19 in `HANDOVER.md`). Each subdirectory is one
stage of the roadmap, and each file is one idea. Unlike `tech-debt/`, these files are pitches: what the idea is, why
it matters (with evidence), then either the options with one recommendation (always Claude's, never a decision) or,
where Jack has decided, the decision with its date and call id. Each ends with the effort, the revenue impact, what
it depends on (often a `tech-debt/` file), and whether it needs a call from Jack. An idea marked **Needs Jack: yes**
goes to him as a pitch before anything is built on it; one marked **no** can be built as written.

The backlog burns down by deletion. When an idea ships, its file goes in the PR that ships it. When Jack rejects one,
its file goes too, and `HANDOVER.md` ("Set aside, with reasons") records why. Each deletion also removes the idea's
line below and fixes the counts. The evidence behind the market and platform claims is in
[market-scan.md](market-scan.md).

**Stages** (one directory each):

- **Release blocker:** the app cannot be submitted, or should not reach strangers, without it.
- **v1 must-have:** ships in 1.0, because App Review and the first users judge the app on it.
- **Insights:** the journal's point. What cannot be backfilled (detail, triggers) is captured from 1.0; the analysis,
  Health and Calendar arrive as Pro in 1.1, and read history from before they were switched on.
- **Monetisation:** the one-time Pro unlock, in 1.1.
- **Growth / later:** after 1.1.

Effort runs S, M, L, XL.

**23 ideas: 7 release blockers, 4 v1 must-haves, 6 insights, 3 monetisation, 3 growth/later. 2 need a call from
Jack** (content-free analytics, reminders). Removed in this rework: the Android release (C6), harm-reduction framing (C16), and the moderation,
alcohol-only and quit-counter positionings (C15).

Each list is in the recommended build order.

## Release blockers (7)

- [Position the app as a neutral journal for learning about yourself](release-blockers/positioning-and-target-user.md). S. Decided (C15)
- [Keep the framing neutral, rate the app 18+, and show a disclaimer](release-blockers/neutral-framing-and-age-rating.md). S. Decided (C16, `r2-age`)
- [Harden the backend before strangers can install the app](release-blockers/backend-hardening.md). M, waits on the paid team; bounded activity queries and App Check wiring built in #55
- [Publish a privacy policy, App Privacy labels and the Health and Calendar disclosures](release-blockers/privacy-policy-and-labels.md). M. No policy for now (`r2-privacy`)
- [Build the Support, About and legal pages the listing and Settings point to](release-blockers/support-about-and-legal-pages.md). S. Waits on a release
- [Generate store screenshots from the e2e harness](release-blockers/store-icon-and-screenshots.md). M
- [Ship a signed iOS build through TestFlight, then the store](release-blockers/ios-release-pipeline-and-testflight.md). L. Decided (C6, `r2-testflight`); blocked on the paid team

## v1 must-haves (4)

- [Add only content-free product analytics, if any](v1-must-haves/crash-reporting-and-analytics.md). S, Needs Jack
- [Add Sign in with Apple to the guest start](v1-must-haves/guest-mode-and-sign-in.md). S. Guest start shipped; waits on the paid team
- [Offer one optional daily check-in that closes the day's journal](v1-must-haves/evening-check-in-and-reminders.md). M. The check-in is ruled out (`r2-days`); reminders alone Needs Jack
- [Ship macOS as a full target on the same App Store record](v1-must-haves/macos-target.md). L. Decided (C6, `r2-mac`)

## Insights (6)

- [Log each entry at maximum granularity, and grow the data model without breaking old clients](insights/granular-logging-and-data-model.md). M, 1.0. Decided (B, 2026-11-06); `amount`, `category` and `triggers` shipped
- [Show the journal's trends: time of day, weekday, and vices side by side](insights/trend-views.md). M, 1.0 free, overlays 1.1 Pro
- [Build an on-device insights engine that separates vices and refuses to report noise](insights/insights-engine.md). XL, 1.1 Pro
- [Read Apple Health, including years of history, to see what follows each vice](insights/apple-health-correlation.md). L, 1.1 Pro
- [Read the calendar on the device to see which events come before use](insights/calendar-integration.md). M, 1.1 Pro
- [Close each week with a review of what the journal found](insights/weekly-review.md). M, 1.1 Pro

## Monetisation (3)

- [Sell the insights once: free journal in 1.0, a one-time Pro unlock in 1.1](monetisation/business-model-and-paywall.md). M. Decided (C17, `r2-pro`)
- [Add purchase, restore and an entitlement check behind one provider](monetisation/iap-and-entitlements.md). M. Decided (`r2-billing`)
- [Let users name their own units and set a cost per unit, for spend](monetisation/units-and-cost-per-unit.md). M

## Growth / later (3)

- [Log from the home screen, the Mac menu bar, Siri and Shortcuts](growth-later/widgets-and-shortcuts.md). XL
- [Add an app lock and a discreet mode for people journaling sensitive habits](growth-later/app-lock-and-discreet-mode.md). S. Decided (`r2-applock`)
- [Let a vice carry an optional goal, never a required one](growth-later/optional-goals-and-limits.md). M

## Where the path stands

The decided calls are C6, C15–C19 and the round-2 calls in `HANDOVER.md`. Built: the Day Dial Today, the one-tap log,
trigger tagging, the decimal amount and vice category, end-to-end encryption of the journal, guest start, Crashlytics and
the macOS target. Left, in Claude's order:

1. **The rest of 1.0's capture:** the context fields and the detail sheet after a tap
   ([granular logging](insights/granular-logging-and-data-model.md)), then the free trend views.
2. **Store material, once there is a paid Apple team** (Jack is not getting one for now): screenshots, the support and
   legal pages, 18+, TestFlight, Sign in with Apple, then the store. The privacy policy waits until and unless Jack
   decides to sell.
3. **1.1 adds Pro as one StoreKit 2 purchase:** the on-device insights engine, Apple Health with its history,
   Calendar, the weekly review and trend overlays.
4. **After 1.1:** self-experiments (randomised n-of-1 tests of a found association), widgets, App Intents and the Mac
   menu bar, optional goals, and import from other journals.

## Needs Jack

- **Analytics:** how much content-free analytics "on your device" can carry, decided at 1.1? (Crashlytics shipped.)
- **Reminders:** the daily check-in is ruled out (`r2-days`), but are reminders wanted?

Decided and recorded in `HANDOVER.md`: end-to-end encryption, 18+, the Mac, Pro at $24.99, StoreKit 2, TestFlight on
production, guests, presets, triggers, Today, the icon, app lock free, no privacy policy for now.
