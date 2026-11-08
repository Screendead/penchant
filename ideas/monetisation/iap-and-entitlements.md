# Add purchase, restore and an entitlement check behind one provider

**Priority:** monetisation

## What

Buy Pro, Restore Purchases, and an entitlement the UI reads to show or hide Pro features, exposed through one
hand-written `StreamProvider` (the style of `lib/providers/`) so the source behind it can change. Pro is one
non-consumable product on one App Store record shared by iOS and macOS.

## Why

- SOURCED ([Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/)): unlocking features requires
  in-app purchase.
- From memory, to verify: review expects a Restore Purchases control for non-consumables, and universal purchase
  makes one purchase valid on iOS and macOS.
- SOURCED (C6, C7): Android, web and `functions/` are going, so there is no cross-store receipt to reconcile and no
  server to validate on.

## Options

- **A. StoreKit 2 through the official `in_app_purchase` plugin.** StoreKit 2 signs transactions, and the device can
  verify them; the entitlement comes from the current transactions. No vendor and no revenue share.
- **B. RevenueCat** (`purchases_flutter`). Dashboards and paywall experiments, for a revenue share above a free
  threshold (check current terms).

## Recommendation

Claude's recommendation: **A.** With Apple platforms only and a single non-consumable, a vendor buys little. Gate Pro
in the client only: Pro features are views over the user's own data, so a bypass costs a sale, not data. Revisit B if
pricing experiments become worth their cut. Check that the Flutter plugin exposes StoreKit 2's verified transactions
before building.

**Effort:** M

**Revenue impact:** Gating: nothing earns without it.

**Depends on:** [business model](business-model-and-paywall.md); [iOS release pipeline](../release-blockers/ios-release-pipeline-and-testflight.md).

**Needs Jack:** no. StoreKit 2 directly (`r2-billing`, Jack, 2026-11-06); parked with the store work.
