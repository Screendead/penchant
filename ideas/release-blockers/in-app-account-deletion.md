# Offer in-app account deletion that removes the data and the Auth user

**Priority:** release blocker

## What

Add a "Delete account" action to Account Settings. It explains what will be removed, re-authenticates the user, deletes every `vices` and `activities` document whose `ownerID` is the user's uid, and then deletes the Firebase Auth user. The data goes first, because Firebase never reissues a UID: if the Auth user went first, the documents would be orphaned for good.

## Why

- SOURCED ([Apple 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/), [Apple's guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app)): an app that supports account creation must offer deletion inside the app, and it must not be unnecessarily difficult. The app registers users (`lib/register.dart`), so this blocks iOS submission.
- SOURCED (register): there is no deletion path, every activity delete is denied by the rules, and nothing calls reauthenticate. `user.delete()` needs a recent login.

## Options

- **A. Client-side:** re-authenticate, delete the documents in batched writes (verify the current batch limit in the Firestore docs), then call `user.delete()`. This needs no server.
- **B. Callable Cloud Function** using the Admin SDK. More robust, but `functions/` does not build and needs the Blaze plan (HANDOVER J2).
- **C. Firebase "Delete User Data" extension.** Verify whether it can delete top-level collections queried by an `ownerID` field, or only `{UID}`-templated paths. If it cannot, it does not fit this schema.
- **D. Deletion by email request.** Apple allows this only for regulated industries, so it is not acceptable here.

## Recommendation

Claude's recommendation, not a decision: **A.** It reuses rules that must be fixed anyway, and it can be tested end to end on the emulators. If the Auth delete fails after the data is gone, the user is left with an empty account, which is recoverable. Clear the local cache afterwards (`terminate()` and `clearPersistence()`; verify in the docs). Put it next to [data export](../v1-must-haves/data-export.md) so users can export first. Revisit B if `functions/` is kept.

**Effort:** M

**Revenue impact:** A release blocker. There is no iOS release, and so no revenue, without it.

**Depends on:**
- `activity-deletes-permitted-by-no-rule` (fixed in PR #27; live once the rules are deployed)
- `write-rules-authorize-on-the-post-write-owner` (fixed in PR #27; live once the rules are deployed)
- [`profile-update-never-reauthenticates`](../../tech-debt/auth-and-account-lifecycle/profile-update-never-reauthenticates.md)
- [`sign-out-leaves-firestore-cache-on-device`](../../tech-debt/auth-and-account-lifecycle/sign-out-leaves-firestore-cache-on-device.md)
- [`no-account-deletion-or-data-export`](../../tech-debt/auth-and-account-lifecycle/no-account-deletion-or-data-export.md)

**Needs Jack:** no. He only needs to approve the confirmation copy.
