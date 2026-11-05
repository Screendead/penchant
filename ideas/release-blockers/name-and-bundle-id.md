# Lock the bundle ID and clear the Penchant name before the first upload

**Priority:** release blocker

## What

The brand is applied in the app's strings: the `MaterialApp` title, the iOS and macOS display and bundle names, the
pubspec description, the README and the app's wording ("habit", not "vice"). Left: change the iOS and macOS bundle IDs
to `com.screendead.penchant`, swap in the Firebase config files for the new app registrations, and choose the domain
variant before the first TestFlight upload.

## Decision

- Decided by Jack 2026-11-03 (C19): **a distinct brand plus a descriptive subtitle.**
- Decided by Jack 2026-11-05 (`r2-brand`): **Penchant**, with the App Store subtitle **"Habit journal & sleep
  insights"** (30 characters). Backups from the pitch: Kenning, then Sounding.
- Decided by Jack 2026-11-05: **no trademark search** will be done. Don't raise it again.
- Decided by Jack 2026-11-05: the app says **"habits"**, not "vices". Stored data, routes and code keep `vice`.

Android and web are removed (C6), so there is no applicationId or web manifest to rename.

## Why

- SOURCED (repo): the bundle ID is still `com.screendead.tracker.tracker` on iOS and macOS, and the macOS Firebase
  config carries the iOS test bundle ID (register).
- From memory, to verify: an App Store Connect record's bundle ID cannot change once a build is uploaded, and iOS and
  macOS sharing one bundle ID lets the Mac app share the iPhone app's record and Pro purchase (universal purchase).
- The 2026-11-03 quick check of Penchant (web search of App Store listings, brand conflicts, DNS and whois) found no app
  and no software or wellness brand on it. `penchant.com` is held through MarkMonitor (a brand owner, unknown) and `penchant.app` is parked,
  so the domain is a variant (`getpenchant.app`, `penchantjournal.com`) or a purchase. Evidence is in the
  [market scan](../market-scan.md), "Brand quick check".

## Remaining steps

1. Done 2026-11-05: Jack registered the iOS app `com.screendead.penchant` in Firebase and supplied its
   `GoogleService-Info.plist`; the Mac shares it (`r2-mac-config`, recommended side).
2. Claude switches both bundle IDs and both config files (and `firebase_options.dart`) in one PR, before any
   TestFlight upload. The phone then sees it as a new app: the old install stays beside it until deleted, and the new
   one starts signed out.
3. Before the first upload: a direct App Store search on a device, and the domain variant.

**Effort:** S

**Revenue impact:** A release prerequisite, because of the bundle-ID lock-in; a rename after launch costs reviews and
ranking.

**Depends on:**
[`macos-firebase-config-carries-the-ios-test-bundle-id`](../../tech-debt/platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md).

**Needs Jack:** yes — the domain variant.
