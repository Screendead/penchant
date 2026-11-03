# Apply the brand everywhere and lock the bundle ID before the first upload

**Priority:** release blocker

## What

Once Jack picks the [brand](brand-name.md), make every identity string match it: the `MaterialApp` title, the iOS and
macOS display and bundle names, the pubspec name and description, and the README. Change the iOS and macOS bundle IDs
to `com.screendead.<brand>`, register the new app IDs in Firebase, and regenerate the Apple platform config.

## Decision

Decided by Jack 2026-11-03 (C19): **a distinct brand plus a descriptive subtitle.** The brand itself is open, pitched
in [brand name](brand-name.md). Android and web are removed (C6), so there is no applicationId or web manifest to
rename.

## Why

- SOURCED (repo): the in-app title is "Vice Tracker" (`lib/main.dart`), `CFBundleDisplayName` is "Tracker", the bundle
  ID is `com.screendead.tracker.tracker`, and the pubspec description is "A new Flutter project."
- SOURCED (register): the macOS Firebase config carries the iOS test bundle ID.
- From memory, to verify: an App Store Connect record's bundle ID cannot change once a build is uploaded.

## Recommendation

Claude's recommendation: one PR, done after the brand call and before any TestFlight upload, screenshots or
marketing. Registering the apps in the Firebase console is a production action, so Jack does it.

**Effort:** S

**Revenue impact:** A release prerequisite, because of the bundle-ID lock-in.

**Depends on:** [brand name](brand-name.md); [`placeholder-app-identity-strings`](../../tech-debt/platform-and-delivery-config/placeholder-app-identity-strings.md); [`macos-firebase-config-carries-the-ios-test-bundle-id`](../../tech-debt/platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md).

**Needs Jack:** no, beyond the brand. He registers the Firebase apps.
