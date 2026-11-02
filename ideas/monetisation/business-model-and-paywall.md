# Charge once for depth, never for the number of vices

**Priority:** monetisation

## What

Decide how the app charges and where the paywall line sits. There is nothing paid today: `pubspec.yaml` has no purchase plugin and `lib/` has no entitlement. The code already has a natural seam: the day dropdown offers only the last 30 days (`lib/vice_tracker.dart:80`, `List.generate(30, …)`), and the Graph tab offers ranges.

## Why

- SOURCED ([market scan](../market-scan.md)):
  - Generic trackers usually cap the free tier at 2–3 habits (Quitzilla 2, Habitify 3), and users complain about it.
  - Lifetime prices in the sobriety apps sit around $65–90. Generic trackers sell one-time unlocks at $5–30.
  - The top complaints are aggressive paywalls, trials that convert to annual plans unexpectedly (Reframe's BBB F) and support that is hard to reach.
  - All prices are indicative and conflict between sources.
- SOURCED ([Apple 3.1.1, 3.1.2](https://developer.apple.com/app-store/review/guidelines/)): unlocks must use in-app purchase. A subscription must provide ongoing value and say clearly what the user gets before they pay.
- SOURCED (code): fl_chart's radar needs at least 3 entries (`radar_chart_data.dart:298`). A 2-vice free cap therefore shows free users a broken hero chart, and a 3-vice cap gates the multi-vice view that sets the app apart.

## Options

- **A. Free 1.0, then a one-time Pro unlock in 1.1** (indicative $9.99–19.99). Pro adds depth:
  - history and graph ranges beyond 30 days;
  - limit history and "days within limit";
  - weekly insights;
  - widgets;
  - themes.

  Unlimited vices, logging, export and deletion stay free. Accounts created before 1.1 get Pro free.
- **B. Freemium with a 3-vice cap,** and Plus sold monthly, annually and lifetime (the I Am Sober and Quitzilla pattern). The highest ceiling per user, but it caps the differentiator.
- **C. Depth-gated subscription,** monthly and annual with a clear 7-day trial, plus a lifetime option. Recurring revenue, but it carries the 3.1.2(a) "ongoing value" obligation and invites the trial-surprise complaint.
- **D. Free, with a tip jar** (consumable IAP). Lowest friction, and little revenue.

## Recommendation

Claude's recommendation, not a decision: **A.**

- A one-time unlock fits a self-contained tracker with no coaching or content, so it needs no "ongoing value" justification.
- It makes "no subscription traps" a credible marketing line.
- Shipping 1.0 free keeps IAP out of the first review and builds ratings. It also gives [analytics](../v1-must-haves/crash-reporting-and-analytics.md) a baseline to price against.
- Grandfathering 1.0 users heads off "they took features away" reviews.
- Keep C open for a later feature with real running cost, such as an AI coach.
- Check every competitor price in its live App Store listing before setting ours.

**Effort:** M (the decision is S; the paywall screens and copy are M)

**Revenue impact:** Direct, since this is the revenue model. Draw the line too generously and the app earns nothing. Put the radar behind the paywall and it earns one-star reviews.

**Depends on:**
- [positioning](../release-blockers/positioning-and-target-user.md)
- [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md)
- [IAP plumbing](iap-and-entitlements.md)
- [`date-navigation-awaits-a-future-that-never-completes`](../../tech-debt/widget-state-and-view-logic/date-navigation-awaits-a-future-that-never-completes.md)
- [`no-query-is-bounded-or-paginated`](../../tech-debt/firebase-data-layer/no-query-is-bounded-or-paginated.md)

**Needs Jack:** yes — Which model (A–D), at what price, and is a subscription ever on the table?
