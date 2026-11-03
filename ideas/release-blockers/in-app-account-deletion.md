# Offer in-app account deletion that removes the data and the Auth user

**Priority:** release blocker

## What

Add "Delete account" to Account Settings. It says what will be removed, re-authenticates, deletes every `vices` and
`activities` document (and any later per-user collection, such as triggers) whose `ownerID` is the user's uid, deletes
the on-device insight store and caches, and then deletes the Firebase Auth user. Data goes first: Firebase never
reissues a uid, so documents left behind an Auth delete are orphaned for good. Health and calendar data stay in the
system stores; the app only drops what it derived from them.

## Why

- SOURCED ([Apple 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/),
  [Apple's guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app)): an app that supports
  account creation must offer deletion in the app, without unnecessary difficulty. The app registers users
  (`lib/register.dart`), so this blocks submission.
- SOURCED (register): nothing calls reauthenticate, and `user.delete()` needs a recent sign-in.

## Options

- **A. Client-side:** re-authenticate, delete the documents in batched writes (check the current batch limit in the
  Firestore docs), then `user.delete()`. No server, and testable end to end on the emulators.
- **B. Firebase "Delete User Data" extension.** Check whether it can delete top-level collections by an `ownerID`
  field rather than `{UID}` paths; if not, it does not fit this schema.

A Cloud Function is no longer an option: `functions/` is being deleted (C7).

## Recommendation

Claude's recommendation: **A.** If the Auth delete fails after the data is gone, the user is left with an empty,
recoverable account. Clear the local Firestore cache afterwards (`terminate()` and `clearPersistence()`; check the
docs). Put it beside [data export](../v1-must-haves/data-export.md) so users can export first.

**Effort:** M

**Revenue impact:** A release blocker.

**Depends on:**
- [`profile-update-never-reauthenticates`](../../tech-debt/auth-and-account-lifecycle/profile-update-never-reauthenticates.md)
- [`sign-out-leaves-firestore-cache-on-device`](../../tech-debt/auth-and-account-lifecycle/sign-out-leaves-firestore-cache-on-device.md)
- [`no-account-deletion-or-data-export`](../../tech-debt/auth-and-account-lifecycle/no-account-deletion-or-data-export.md)

**Needs Jack:** no. He approves the confirmation copy.
