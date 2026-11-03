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

**34 ideas: 12 release blockers, 9 v1 must-haves, 7 insights, 3 monetisation, 3 growth/later. 18 need a call from
Jack.** Removed in this rework: the Android release (C6), harm-reduction framing (C16), and the moderation,
alcohol-only and quit-counter positionings (C15).

Each list is in the recommended build order.

## Release blockers (12)

- [Position the app as a neutral journal for learning about yourself](release-blockers/positioning-and-target-user.md). S. Decided (C15)
- [Pick the brand: Penchant, with a descriptive subtitle](release-blockers/brand-name.md). S, Needs Jack
- [Apply the brand everywhere and lock the bundle ID before the first upload](release-blockers/name-and-bundle-id.md). S. Decided pattern (C19)
- [Keep the framing neutral, rate the app 18+, and show a disclaimer](release-blockers/neutral-framing-and-age-rating.md). S. Decided (C16), Needs Jack
- [Harden the backend before strangers can install the app](release-blockers/backend-hardening.md). M
- [Encrypt what each entry says on the device before it syncs, and keep the dates plaintext](release-blockers/end-to-end-encryption.md). L, Needs Jack
- [Offer in-app account deletion that removes the data and the Auth user](release-blockers/in-app-account-deletion.md). M
- [Give every build a unique version, a tag and a changelog entry](release-blockers/versioning-and-changelog.md). S
- [Publish a privacy policy, App Privacy labels and the Health and Calendar disclosures](release-blockers/privacy-policy-and-labels.md). M, Needs Jack
- [Build the Support, About and legal pages the listing and Settings point to](release-blockers/support-about-and-legal-pages.md). S, Needs Jack
- [Make a final icon and generate store screenshots from the e2e harness](release-blockers/store-icon-and-screenshots.md). M, Needs Jack
- [Ship a signed iOS build through TestFlight, then the store](release-blockers/ios-release-pipeline-and-testflight.md). L. Decided (C6), Needs Jack

## v1 must-haves (9)

- [Add crash reporting before TestFlight, and only content-free analytics](v1-must-haves/crash-reporting-and-analytics.md). S, Needs Jack
- [Let people start without an account, and finish the basic sign-in flows](v1-must-haves/guest-mode-and-sign-in.md). M, Needs Jack
- [Make logging work with no signal, and say so in the listing](v1-must-haves/offline-first.md). M
- [Log in one tap, then add detail without being made to](v1-must-haves/one-tap-quick-logging.md). M
- [Make Today a journal of the day: a timeline, per-vice tiles and the chart](v1-must-haves/today-screen-rework.md). L. Chart and clean day decided (C2, C5), Needs Jack
- [Offer one optional daily check-in that closes the day's journal](v1-must-haves/evening-check-in-and-reminders.md). M, Needs Jack
- [Get a new user from install to a first log in under a minute](v1-must-haves/first-run-onboarding.md). M, Needs Jack
- [Let every user export their data as CSV and JSON](v1-must-haves/data-export.md). S
- [Ship macOS as a full target on the same App Store record](v1-must-haves/macos-target.md). L. Decided (C6), Needs Jack

## Insights (7)

- [Log each entry at maximum granularity, and grow the data model without breaking old clients](insights/granular-logging-and-data-model.md). M, 1.0. Vice fields decided (C18), Needs Jack
- [Tag what led to each entry, from a tree that learns your common triggers](insights/trigger-tagging.md). M, 1.0, Needs Jack
- [Show the journal's trends: time of day, weekday, and vices side by side](insights/trend-views.md). M, 1.0 free, overlays 1.1 Pro
- [Build an on-device insights engine that separates vices and refuses to report noise](insights/insights-engine.md). XL, 1.1 Pro
- [Read Apple Health, including years of history, to see what follows each vice](insights/apple-health-correlation.md). L, 1.1 Pro
- [Read the calendar on the device to see which events come before use](insights/calendar-integration.md). M, 1.1 Pro
- [Close each week with a review of what the journal found](insights/weekly-review.md). M, 1.1 Pro

## Monetisation (3)

- [Sell the insights once: free journal in 1.0, a one-time Pro unlock in 1.1](monetisation/business-model-and-paywall.md). M. Decided (C17), Needs Jack
- [Add purchase, restore and an entitlement check behind one provider](monetisation/iap-and-entitlements.md). M, Needs Jack
- [Let users name their own units and set a cost per unit, for spend](monetisation/units-and-cost-per-unit.md). M

## Growth / later (3)

- [Log from the home screen, the Mac menu bar, Siri and Shortcuts](growth-later/widgets-and-shortcuts.md). XL
- [Add an app lock and a discreet mode for people journaling sensitive habits](growth-later/app-lock-and-discreet-mode.md). S, Needs Jack
- [Let a vice carry an optional goal, never a required one](growth-later/optional-goals-and-limits.md). M

## Recommended path to a paid release

Claude's recommended sequence. The decided calls are C6 and C15–C19; every "Needs Jack" item in it is still open.

1. **Jack makes the five calls 1.0 hangs on:** the brand (and so the bundle ID), extending C18 to activity fields and
   the `days` and `triggerNodes` collections, 18+ in place of the retired 17+, Mac in 1.0 or 1.0.x, and whether 1.0
   seals what each entry says (end-to-end encryption).
2. **Meanwhile agents build what needs no call,** beside the wave-2 debt: parsers that default every missing field
   (before any new field is written), backend hardening, account deletion, versioning, offline logging, export and
   one-tap logging.
3. **End-to-end encryption, if Jack picks it,** lands next: after the parser defaults, the shared write layer,
   bounded queries, the bundle-ID lock and the macOS target at 11 or later, and before any granular field is written,
   so those fields are sealed from their first write. Its rules (R1) and fourth index reach production before the
   build that migrates.
4. **1.0 captures everything that cannot be backfilled:** the granular fields, trigger tagging, the check-in, the
   timeline Today and the free trend views. Health and Calendar history can be read later, so they wait for 1.1.
5. **Store material:** the brand applied, privacy policy, support pages, neutral copy and disclaimer, 18+, icon and
   automated screenshots; then internal and external TestFlight on a separate beta Firebase project, as a review
   rehearsal.
6. **1.0 ships free on iOS,** with the Mac on the same record if its e2e run is green, otherwise in 1.0.x. No in-app
   purchase in the first review; Crashlytics only.
7. **1.1 adds Pro as one purchase through StoreKit:** the on-device insights engine, Apple Health with its history,
   Calendar, the weekly review and trend overlays, plus content-free funnel events and a legally reviewed privacy
   policy. Everything free in 1.0 stays free, so no grandfathering is needed.
8. **After 1.1:** self-experiments (randomised n-of-1 tests of a found association), widgets, App Intents and the Mac
   menu bar, the app lock and discreet mode, optional goals, and import from other journals.

## Needs Jack

- **Brand:** Penchant (recommended), Kenning or Sounding; which subtitle; pay for a trademark search first?
- **End-to-end encryption:** seal names, units, amounts and later notes before 1.0, with an iCloud Keychain key and a
  recovery key (recommended), defer to 1.1, skip it, or hide timing too; accept C12 and C13 as app-only checks and
  the visible "when"?
- **Data model:** extend C18 to fields on `activities`, the `days` and `triggerNodes` collections, and decimals through a separate `amount` field?
- **Age rating:** confirm 18+, since Apple retired 17+ in 2025.
- **Mac:** ship in 1.0 or 1.0.x, and confirm Health results never sync to the Mac?
- **Pro line and price:** the analysis layer as Pro at USD 24.99 (recommended), or a different line?
- **Billing:** StoreKit only (recommended), or RevenueCat and its revenue share?
- **TestFlight:** pay for the Developer Program, name the beta testers, and use a separate beta Firebase project?
- **Privacy policy:** legal entity, contact and data-controller details, and a paid legal review before 1.1?
- **Support:** the support address, and Firebase Hosting or the brand domain for the legal pages?
- **Icon:** Jack, a commissioned designer, or generated candidates?
- **Crash reporting and analytics:** Crashlytics alone at launch, and how much analytics "on your device" can carry later?
- **Guests:** allow anonymous start in 1.0, accepting that an unlinked guest who deletes the app loses their data?
- **Check-in:** record "nothing logged today" in a new `days` collection?
- **Onboarding presets:** which starter vices, worded how?
- **Triggers:** approve the starter tree's top two levels.
- **Today:** sign off the layout from a mock-up.
- **App lock and discreet mode:** free or Pro?
