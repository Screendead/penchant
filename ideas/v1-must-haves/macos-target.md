# Ship macOS as a full target on the same App Store record

**Priority:** v1 must-have

## What

"Fully supported" (C6), scoped:

- **Builds and runs:** the macOS tree brought current (deployment target, pods, sandbox network entitlement, its own
  Firebase config), a `tools/e2e.sh` path that runs the integration tests as a macOS app against the emulators, and a
  CI build. Queue item 2 does this part.
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
- SOURCED (register): the macOS deployment target is frozen at 10.14, the sandbox grants no outbound network, the
  lockfile has no Firebase pods, the Firebase config carries the iOS test bundle ID, and the platform is undocumented.
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
- [`macos-deployment-target-frozen-at-10-14`](../../tech-debt/platform-and-delivery-config/macos-deployment-target-frozen-at-10-14.md)
- [`macos-sandbox-grants-no-outbound-network`](../../tech-debt/platform-and-delivery-config/macos-sandbox-grants-no-outbound-network.md)
- [`macos-tree-is-stale-and-lockfile-has-no-firebase-pods`](../../tech-debt/platform-and-delivery-config/macos-tree-is-stale-and-lockfile-has-no-firebase-pods.md)
- [`macos-firebase-config-carries-the-ios-test-bundle-id`](../../tech-debt/platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md)
- [`macos-platform-is-undocumented`](../../tech-debt/repo-docs-and-release-hygiene/macos-platform-is-undocumented.md)
- [name and bundle ID](../release-blockers/name-and-bundle-id.md)

**Needs Jack:** yes — Mac in 1.0 or 1.0.x, and confirm Health results never sync to the Mac.
