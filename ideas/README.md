# Product ideas backlog

These are the things worth building between today's app and a paid release, as of 2026-11-02. Each subdirectory is
one stage of the roadmap, and each file is one idea. Unlike `tech-debt/`, these files are pitches. Each one says
what the idea is, why it matters (with evidence), gives 2–4 options and one reasoned recommendation, then states
the effort, the revenue impact, what it depends on (often a `tech-debt/` file), and whether it needs a call from
Jack. Every recommendation is Claude's, not a decision. An idea marked **Needs Jack: yes** goes to him as a pitch
before anything is built on it. An idea marked **no** can be built as written.

The backlog burns down by deletion. When an idea ships, its file goes in the PR that ships it. When Jack rejects
one, its file goes too, and a line in `HANDOVER.md` ("Set aside, with reasons") records the rejection and its
reason. Each deletion also removes the idea's line below and updates the counts. When a directory empties it goes,
and when this directory is gone the roadmap is done. The evidence behind the market claims is in
[market-scan.md](market-scan.md).

**Priority** (one directory each):

- **Release blocker:** the app cannot be submitted, or should not be exposed to strangers, without it.
- **v1 must-have:** it ships in 1.0, because App Review and the first users judge the app on it.
- **Monetisation:** the paid tier and what it sells, arriving in 1.1.
- **Growth / later:** after a paid release.

Effort runs S, M, L, XL.

**26 ideas: 10 release blockers, 9 v1 must-haves, 4 monetisation, 3 growth/later. 18 need a call from Jack.**

One question cuts across several ideas, so ask it once. The standing rule says the documented Firestore shape must
stay. Do new *optional* fields on `vices` or `activities` keep that shape? The ideas that need an answer are goals
and limits, units and cost, context tags, and free-day check-ins.

Each list below is in the recommended build order.

## Release blockers (10)

- [Position the app as a multi-substance moderation logger](release-blockers/positioning-and-target-user.md). S, Needs Jack
- [Lock the public name and bundle ID before the first TestFlight upload](release-blockers/name-and-bundle-id.md). S, Needs Jack
- [Frame the app as harm reduction so it clears App Store guidelines 1.4.1 and 1.4.3](release-blockers/substance-framing-and-age-rating.md). M, Needs Jack
- [Harden the backend before strangers can install the app](release-blockers/backend-hardening.md). M
- [Offer in-app account deletion that removes the data and the Auth user](release-blockers/in-app-account-deletion.md). M
- [Publish a privacy policy, App Privacy labels and a health-data consent step](release-blockers/privacy-policy-and-labels.md). M, Needs Jack
- [Build the Support, About and legal pages the listing and Settings point to](release-blockers/support-about-and-legal-pages.md). S, Needs Jack
- [Give every build a unique version, a tag and a changelog entry](release-blockers/versioning-and-changelog.md). S
- [Make a final icon and generate store screenshots from the e2e harness](release-blockers/store-icon-and-screenshots.md). M, Needs Jack
- [Ship a signed native iOS build through TestFlight before the public launch](release-blockers/ios-release-pipeline-and-testflight.md). L, Needs Jack

## v1 must-haves (9)

- [Add crash reporting before TestFlight, and only content-free analytics](v1-must-haves/crash-reporting-and-analytics.md). S, Needs Jack
- [Let people start without an account, and finish the basic sign-in flows](v1-must-haves/guest-mode-and-sign-in.md). M, Needs Jack
- [Give each vice a goal and a limit, so Today can say "on track"](v1-must-haves/per-vice-goals-and-limits.md). M, Needs Jack
- [Log an activity in one tap from Today](v1-must-haves/one-tap-quick-logging.md). M
- [Rebuild Today around progress cards, and keep the radar as an optional view](v1-must-haves/today-screen-rework.md). L, Needs Jack
- [Get a new user from install to a first log in under a minute](v1-must-haves/first-run-onboarding.md). M, Needs Jack
- [Make logging work with no signal, and say so in the listing](v1-must-haves/offline-first.md). M
- [Let every user export their data as CSV and JSON](v1-must-haves/data-export.md). S
- [Remind users once a day, and let them mark a free day from the reminder](v1-must-haves/evening-check-in-and-reminders.md). M, Needs Jack

## Monetisation (4)

- [Charge once for depth, never for the number of vices](monetisation/business-model-and-paywall.md). M, Needs Jack
- [Add purchase, restore and an entitlement check behind one provider](monetisation/iap-and-entitlements.md). L, Needs Jack
- [Sell a weekly insights report computed on the device](monetisation/weekly-insights-and-context-tags.md). L
- [Let users define their own units and a cost per unit, for "money saved"](monetisation/units-and-cost-per-unit.md). M, Needs Jack

## Growth / later (3)

- [Log from the home screen, from Siri and into Apple Health](growth-later/widgets-shortcuts-and-health.md). XL
- [Add an app lock and a discreet mode for people logging sensitive habits](growth-later/app-lock-and-discreet-mode.md). S, Needs Jack
- [Release on Android once its build works and is release-signed](growth-later/android-release.md). L, Needs Jack

## Recommended path to a paid release

This is Claude's recommended sequence. Every "Needs Jack" item in it is still undecided.

1. Jack makes the four calls everything else hangs on: the positioning, the name and bundle ID, the business model, and whether optional Firestore fields keep the shape.
2. Meanwhile, agents build the blockers that need no call (backend hardening, account deletion, versioning) alongside the wave-2 tech debt.
3. Next come the v1 must-haves: Crashlytics, guest start, goals and limits, one-tap logging, the Today rework, onboarding, offline logging, export and reminders.
4. Then the store material: the privacy policy, the support pages, the harm-reduction copy, the icon and the screenshots. Internal and then external TestFlight serves as a dress rehearsal for review.
5. 1.0 ships free on iOS, to earn ratings and a funnel baseline. There is no IAP in the first review.
6. 1.1 adds the one-time Pro unlock. It sells depth (history beyond 30 days, limit history, weekly insights), never a cap on vices, and accounts from 1.0 get it free.
7. After that, Pro grows with money saved and insights, and the app with widgets, Health and Android.
