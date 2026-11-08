# Add Sign in with Apple to the guest start

**Priority:** v1 must-have

## State

Jack picked **C** on 2026-11-06 (`r2-signin`). Shipped: "Start without an account" signs in anonymously, and
Account Settings links an email and password to the same uid. Left: Sign in with Apple, which needs the paid Apple
developer team Jack is not getting for now, and the production Anonymous provider switch in the Firebase console (Jack).

## Left

Sign in with Apple, to put an email-and-password account's data on the user's Apple ID: linking the Apple credential
to the signed-in user keeps the uid, so the data needs no copy. From memory, to verify: guideline 4.8 requires an
Apple or equivalent private login whenever a third-party social login is offered, and Apple-only avoids the question.
Test the linking edge cases end to end in the Auth emulator.

**Effort:** S

**Revenue impact:** Medium: one tap puts the Mac on the same data.

**Depends on:** the paid Apple developer team (`HANDOVER.md`, B2).

**Needs Jack:** no. Guests are allowed (`r2-signin`, 2026-11-06); only the paid team and the production Anonymous
provider switch in the Firebase console wait on him.
