# Let people start without an account, and finish the basic sign-in flows

**Priority:** v1 must-have

## What

Today `main.dart` sends anyone not signed in to an email-and-password screen before they see anything. Password
reset, a verification email on sign-up and readable sign-up errors exist (`lib/account/`). The proposal:

- On first launch, sign in with Firebase anonymous auth.
- Offer "Back up and sync" later, which links an email or Apple credential to the same uid.

## Why

- SOURCED ([Apple 5.1.1](https://developer.apple.com/app-store/review/guidelines/)): an app without significant
  account-based features should work without a login. This app's only account feature is sync, which now also means
  sync between iPhone and Mac.
- SOURCED (register): a signed-in user briefly sees the login screen on every cold start, and nothing gates on a
  verified address.
- INFERENCE: people journaling drug use or gambling are the least willing to hand over an email before seeing value.
- From the Firebase docs, to verify: linking keeps the uid, so the `ownerID` rules and the data shape are unchanged.

## Options

- **A.** Email only, as today.
- **B.** Anonymous start with optional linking, plus everything in A.
- **C.** B, plus Sign in with Apple. From memory, to verify: guideline 4.8 requires an Apple or equivalent private
  login whenever a third-party social login is offered; Apple-only avoids the question.
- **D.** Local-only storage for guests, migrated on sign-up. It doubles the data layer.

## Recommendation

Claude's recommendation: **C in 1.0.** With Android and web gone (C6), every user has an Apple ID, and Sign in with
Apple is the one-tap way to get a second device (the Mac) on the same data. Test the linking edge cases end to end in
the Auth emulator.

**Effort:** M

**Revenue impact:** High: more installs reach a first log, and linking is a natural soft-upsell moment.

**Depends on:**
- [`no-email-verification`](../../tech-debt/auth-and-account-lifecycle/no-email-verification.md)
- [`auth-loading-is-treated-as-signed-out`](../../tech-debt/widget-state-and-view-logic/auth-loading-is-treated-as-signed-out.md)

**Needs Jack:** yes — Allow guests in 1.0, and accept that a guest who deletes the app without linking loses their
data (behind a clear warning)?
