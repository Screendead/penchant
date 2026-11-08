# Sell the insights once: free journal in 1.0, a one-time Pro unlock in 1.1

**Priority:** monetisation

## What

What is left of the business model is the line between free and Pro, and the price. There is nothing paid today:
`pubspec.yaml` has no purchase plugin and `lib/` has no entitlement.

## Decision

Decided by Jack 2026-11-03 (C17): **free 1.0, then a one-time Pro unlock in 1.1.** Set aside: a vice-count cap,
subscriptions, and a tip jar.

## Why

- SOURCED ([market scan](../market-scan.md)): insight is what the journals charge for. Bearable gates its Factor
  Effect report (USD 34.99/yr or 6.99/mo); Exist has no free tier (USD 62.90/yr); Daylio's correlations are premium,
  with a reported USD 59.99 lifetime option; Welltory's lifetime is USD 299.99. All indicative.
- SOURCED (same): in the vice category the top complaints are paywalls on basics and trials that turn into annual
  plans.
- INFERENCE: of the apps priced, only Daylio and Welltory sell a one-time purchase, so "pay once, insights on your
  phone" is a distinct offer.
- SOURCED ([Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/)): unlocking features requires
  in-app purchase.

## Options for the line

- **A. Pro is the analysis layer:** the [insights engine](../insights/insights-engine.md),
  [Apple Health](../insights/apple-health-correlation.md), [calendar](../insights/calendar-integration.md), the
  [weekly review](../insights/weekly-review.md), trend overlays, and later widgets and import. Free forever: unlimited
  vices, every logging field and trigger, all history, the basic trends, export, deletion, the Mac app.
- **B.** A, but also history beyond 90 days in Pro.
- **C.** A, but Health correlation free as a hook, with calendar, multi-vice separation and the weekly review Pro.

## Recommendation

Claude's recommendation: **A, at USD 24.99** (indicative band 19.99–29.99; check live listings before setting it).
Capture is free because a journal is worth only what it has recorded; reflection is what costs. No grandfathering is
needed, since nothing free in 1.0 moves behind the paywall; give TestFlight testers Pro through promo or offer codes (from memory, to verify for a non-consumable). Show one
locked insight card, with its real effect blurred, once the engine has something to say: the paywall appears at the
moment of value, never on launch.

**Effort:** M (paywall screens and copy)

**Revenue impact:** Direct: this is the revenue model.

**Depends on:** [IAP plumbing](iap-and-entitlements.md); [insights engine](../insights/insights-engine.md).

**Needs Jack:** no. The analysis layer is Pro at $24.99 (`r2-pro`, Jack, 2026-11-06); parked with the store work.
