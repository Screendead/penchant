# Let people start without an account, and finish the basic sign-in flows

**Priority:** v1 must-have

## What

Today `main.dart` sends any user who is not signed in to an email-and-password screen before they see anything. There is no password reset and no email verification. The proposal has four parts:

- On first launch, sign the user in with Firebase anonymous auth.
- Offer "Back up and sync" later, which links an email credential to the same uid.
- Add forgot-password and verification flows.
- Show readable sign-up errors.

## Why

- SOURCED ([Apple 5.1.1](https://developer.apple.com/app-store/review/guidelines/)): if an app lacks significant account-based features, people should be able to use it without logging in. This app's only account feature is sync.
- SOURCED (register): there is no password reset and no verification. Registration failures are unhandled, and a signed-in user briefly sees the login screen on every cold start.
- INFERENCE: a sign-up wall before the first moment of value is the biggest funnel leak a tracker can have. People logging gambling or drug use are the least willing to hand over an email.
- From the Firebase docs, to verify: linking keeps the uid, so the `ownerID` rules and the data shape are unchanged.

## Options

- **A.** Email only, with reset, verification and readable errors added.
- **B.** Anonymous auth on first launch with optional email linking, plus everything in A.
- **C.** B, plus Sign in with Apple, and Google on Android. From memory, to verify: guideline 4.8 requires a privacy-focused login option whenever a third-party social login is offered.
- **D.** Local-only storage for guests, migrated into Firestore on sign-up. This doubles the data layer.

## Recommendation

Claude's recommendation, not a decision: **B for 1.0, with C in 1.1** when cross-device sync becomes a selling point. B keeps one data path and the current rules. Test the account-linking edge cases end to end in the Auth emulator.

**Effort:** M

**Revenue impact:** High. More installs reach a first log. The link-account prompt is also the natural moment for a soft upsell.

**Depends on:**
- [`no-password-reset-path`](../../tech-debt/auth-and-account-lifecycle/no-password-reset-path.md)
- [`no-email-verification`](../../tech-debt/auth-and-account-lifecycle/no-email-verification.md)
- [`auth-errors-are-surfaced-verbatim`](../../tech-debt/auth-and-account-lifecycle/auth-errors-are-surfaced-verbatim.md)
- [`registration-failures-are-unhandled`](../../tech-debt/error-handling-and-observability/registration-failures-are-unhandled.md)
- [`auth-loading-is-treated-as-signed-out`](../../tech-debt/widget-state-and-view-logic/auth-loading-is-treated-as-signed-out.md)
- [`empty-stream-shortcircuit-reads-as-permanent-loading`](../../tech-debt/widget-state-and-view-logic/empty-stream-shortcircuit-reads-as-permanent-loading.md)

**Needs Jack:** yes — Allow guests in 1.0, and accept that a guest who deletes the app without linking an account loses their data (shown with a clear warning)?
