# Changelog

Newest first. Each release gets a `## [X.Y.Z]` section matching the `version:` in `pubspec.yaml`; the release workflow
publishes that section as the GitHub release notes, and it is the source for the App Store "What's New" text. Add a
line under `[Unreleased]` in the PR that makes the change, worded for the person using the app. Seeded from the merged
pull request titles (`gh pr list --state merged`).

## [Unreleased]

### Added

- Logging works with no signal: an offline banner, a "Not yet synced" mark on entries the server has not received,
  and an empty day offline says the device may not have it rather than calling it clear.
- Account Settings exports your data as CSV and JSON, deletes the account with everything in it, resends the
  verification email and changes the email address; sign-in has a password-reset link. Signing out clears this
  device's copy of your data, and asks first if entries have not synced (#54).

### Changed

- A screen that cannot load its data says why and offers Retry, instead of spinning forever; so does the app when it
  cannot start. Save and delete errors read the same plain wording on every screen, and every error is written to the
  device log.
- Saving, editing, deleting, adding or editing a vice and archiving no longer report a slow connection as a failure:
  after ten seconds the screen closes and says the change will sync. Buttons stay disabled while their change is in flight.
- An archived vice's history stays reachable: its Manage Data row opens it, marked "Archived", and the Graph lists it
  last as "(archived)" instead of opening on it.
- A signed-in launch no longer flashes the sign-in screen while the saved session loads.
- Today and the Graph move on at midnight, and on returning to the app the next day, instead of staying on yesterday.
- The activity editor shows changes made elsewhere while it is open, until you edit that field.
- The Graph keeps its vice, range and smoothing when you switch tabs, and loads only while it is showing.

## [0.1.0] - Unreleased

### Added

- Day navigation, activity history, an activity editor and a usage graph (#28).
- Today shows bars below three vices and the radar from three up, a quiet "clean day" state, a queued-save message
  when a save is waiting to sync, and an 8 second Undo (#36).
- Vices can be archived: an archived vice disappears from recording and from Today but keeps its history (#12).
- The app shows its version and build number under Settings > About.

### Changed

- Firestore rules require a positive quantity, vice names of at most 60 characters, and an activity's vice to belong
  to the person logging it (#33).
- Firestore rules fixed for activity Undo and delete, and for cross-account overwrites (#27).
- Flutter and dependencies upgraded; iOS 26 build stabilised (#12, #13).
- Android, web, Cloud Functions and hosting removed; the app targets iOS and macOS (#34).

### Internal

- Quality gates in CI, pinned Flutter and actions (#25); end-to-end tests on an iOS Simulator against the Firebase
  emulators (#29); handover notes, the tech-debt register and the product ideas backlog (#24, #26, #35).

### Earlier history

- Add vice (#3) and a homepage layout rework (#2).
