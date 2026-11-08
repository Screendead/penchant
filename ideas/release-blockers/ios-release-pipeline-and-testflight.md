# Ship a signed iOS build through TestFlight, then the store

**Priority:** release blocker

## What

1. Join the Apple Developer Program, search the App Store for Penchant on a device, and create the App Store Connect
   record under the bundle ID `com.screendead.penchant` (iOS and macOS since 2026-11-05).
2. Signing, plus a CI upload using an App Store Connect API key.
3. Internal TestFlight for Jack and a few testers.
4. External TestFlight, through Beta App Review: a rehearsal of the full review.
5. Public launch on iOS. The [macOS target](../v1-must-haves/macos-target.md) joins the same record.

The work includes the App Review demo account and short reviewer notes.

Export compliance belongs here: the app does its own AES-256-GCM encryption of the journal, and nothing in `ios/` or
`macos/` sets `ITSAppUsesNonExemptEncryption` or answers the encryption questions yet (SOURCED: grep of both trees,
2026-11-08). Settle it before the first upload.

## Decision

Decided by Jack 2026-11-03 (C6): **iOS first, through TestFlight**, with macOS as a fully supported target; Android and
web are removed. C10 keeps end-to-end runs local, so CI builds and uploads but does not run the simulator suite.

## Why

- SOURCED ([Apple 4.2](https://developer.apple.com/app-store/review/guidelines/)): an app must be more than a
  repackaged website.
- From memory, to verify: an App Store Connect record's bundle ID cannot change once a build is uploaded, and iOS and
  macOS sharing one bundle ID lets the Mac app share the record and the Pro purchase (universal purchase).
- From memory, to verify: internal TestFlight needs no review, external does, and apps with a login must give App
  Review demo credentials.

## Recommendation

Claude's recommendation: Xcode automatic signing with an API key in CI. TestFlight builds point at a separate Firebase
project (for example `screendead-vice-tracker-beta`), so testers never write into production and the bundle-ID change
can be rehearsed. Creating that project is Jack's.

**Effort:** L

**Revenue impact:** The gate to all store revenue.

**Depends on:** the bundle ID (done: `com.screendead.penchant`, 2026-11-05); the domain, for the support and
privacy URLs ([support pages](support-about-and-legal-pages.md)); versioning (done: `CHANGELOG.md`, `tools/build-version.sh`, the Release workflow); account deletion (done: Account Settings, `lib/account/`); [privacy policy](privacy-policy-and-labels.md); [backend hardening](backend-hardening.md) (bounded activity queries and App Check wiring built; the App Attest entitlement needs the paid team); `no-license-file-anywhere` (fixed in PR #34: proprietary LICENSE) (queue 1c, C8).

**Needs Jack:** no call left. Production, no separate beta project (`r2-testflight`, Jack, 2026-11-06); blocked on the paid Apple developer team, which Jack is not getting for now.
