# Changelog

Newest first. Each release gets a `## [X.Y.Z]` section matching the `version:` in `pubspec.yaml`; the release workflow
publishes that section as the GitHub release notes, and it is the source for the App Store "What's New" text. Add a
line under `[Unreleased]` in the PR that makes the change, worded for the person using the app. Seeded from the merged
pull request titles (`gh pr list --state merged`).

## [Unreleased]

## [0.1.0] - Unreleased

### Added

- Day navigation, activity history, an activity editor and a usage graph (#28).
- Today shows bars below three vices and the radar from three up, a quiet "clean day" state, a queued-save message
  when a save is waiting to sync, and an 8 second Undo (#36).
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
