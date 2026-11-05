# Ship macOS as a full target on the same App Store record

**Priority:** v1 must-have

## What

"Fully supported" (C6), scoped:

- **Builds and runs:** the macOS tree brought current (deployment target, pods, sandbox network entitlement, its own
  Firebase config), a `tools/e2e.sh` path that runs the integration tests as a macOS app against the emulators, and a
  CI build. Built in PR #47. The Mac shares the iOS bundle ID `com.screendead.penchant` and its Firebase
  registration and config file (`r2-mac-config`); its development profile was made with
  `-allowProvisioningUpdates` (2026-11-05).
- **Feature parity:** logging, triggers, timeline, trends, export, deletion, calendar correlation, and the insights
  engine all run on the Mac. Apple Health does not (below).
- **Mac-native touches:** keyboard shortcuts for quick log (⌘1–⌘9 per vice), resizable windows with a two-pane layout
  at wide sizes, a menu-bar quick-log item later.
- **Distribution:** the same bundle ID and App Store record as iOS, so one Pro purchase covers both (universal
  purchase; from memory, to verify).

## Decision

Decided by Jack 2026-11-03 (C6): **iOS first, plus a fully supported macOS target.** Open below: when the Mac
ships, and whether anything Health-derived reaches it.

## Why

- SOURCED (C6): "Add a MacOS target too, fully-supported."
- SOURCED ([`isHealthDataAvailable`](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable())):
  on macOS 13 and later the HealthKit framework exists, "but your app can't read or write HealthKit data", and the
  call returns `false`. SOURCED ([Apple DTS, 2025](https://developer.apple.com/forums/thread/798780)): still true.
- SOURCED (repo): the frozen deployment target, the missing network entitlement and the stale lockfile were fixed in
  PR #47; the Firebase config that carried the iOS test bundle ID was replaced by the shared Penchant one
  (2026-11-05).
- SOURCED ([FirebaseAuth 10.5.0 release note](https://github.com/firebase/firebase-ios-sdk/blob/main/FirebaseAuth/CHANGELOG.md)):
  "using Firebase Auth in a Mac app requires that the app is signed with a provisioning profile that has the Keychain
  Sharing capability enabled."
- SOURCED ([EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)): sandboxed macOS
  apps reading calendars also need the `com.apple.security.personal-information.calendars` entitlement.

## Options

- **A.** Mac in 1.0 with Health features hidden; Health insight cards say "available on iPhone".
- **B.** A, plus syncing Health-derived results (not samples) from iPhone to Mac through Firestore. It breaks "Health
  data never leaves your phone" and sits in the grey area of Apple's third-party rules.
- **C.** Mac in a 1.0.x update after the iOS launch.

## Recommendation

Claude's recommendation: **A if the macOS e2e is green when iOS 1.0 is ready, otherwise C;** never block the iOS
launch on the Mac. Do not do B.

**Effort:** L

**Revenue impact:** Medium: a desk-side logging surface for screen-time and caffeine users, and a reason to buy Pro
once for two devices.

**Depends on:**
- `macos-deployment-target-frozen-at-10-14` (fixed in PR #47)
- `macos-sandbox-grants-no-outbound-network` (fixed in PR #47)
- `macos-tree-is-stale-and-lockfile-has-no-firebase-pods` (fixed in PR #47)
- [`macos-release-build-fails-in-flutter-unpack`](../../tech-debt/platform-and-delivery-config/macos-release-build-fails-in-flutter-unpack.md)
- `macos-firebase-config-carries-the-ios-test-bundle-id` (fixed by the bundle-ID switch, 2026-11-05)
- `macos-platform-is-undocumented` (fixed in PR #34: CLAUDE.md documents the platforms)
- name and bundle ID (done 2026-11-05)

**Needs Jack:** yes — Mac in 1.0 or 1.0.x, and confirm Health results never sync to the Mac.
