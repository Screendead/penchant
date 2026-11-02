# Add purchase, restore and an entitlement check behind one provider

**Priority:** monetisation

## What

Add the in-app purchase flow:

- buying Pro;
- Restore Purchases;
- an entitlement that the UI reads to show or hide Pro features.

Expose the entitlement through one hand-written `StreamProvider`, matching the style in `lib/providers/`, so the vendor behind it can be swapped later. Grandfathering can key on the Firebase Auth account's creation time.

## Why

- SOURCED ([Apple 3.1.1](https://developer.apple.com/app-store/review/guidelines/)): unlocking features requires in-app purchase.
- From memory, to verify: review expects a Restore Purchases control for non-consumables.
- INFERENCE: one Firebase account spans iOS, Android and web, so the entitlement should be readable on every platform.
- Gap: the market scan found no RevenueCat terms or conversion data.

## Options

- **A. RevenueCat** (`purchases_flutter`). It handles cross-platform receipts, keys entitlements to the Firebase uid and supports paywall experiments. It charges a revenue share above a free threshold, so verify the current terms.
- **B. The official `in_app_purchase` plugin with a client-side unlock.** No vendor, but no receipt validation, so it is easy to bypass and gives no web entitlement.
- **C. `in_app_purchase` with server-side receipt validation** in a Cloud Function that writes an entitlement field. Correct and vendor-free, but it depends on reviving `functions/` (HANDOVER J2) and on the Blaze plan.

## Recommendation

Claude's recommendation, not a decision: **A.** It is the fastest correct path, and it keeps receipt-validation code out of a project whose `functions/` does not build. Gate Pro features on the client only. The paid features are views over the user's own data, so enforcing them in the rules is not worth the cost at this stage.

**Effort:** L

**Revenue impact:** Gating. Mobile cannot earn anything without it.

**Depends on:** [business model](business-model-and-paywall.md); [iOS release pipeline](../release-blockers/ios-release-pipeline-and-testflight.md).

**Needs Jack:** yes — Accept a billing vendor (RevenueCat) and its revenue share, or pay the build cost of C?
