# Ship a signed iOS build through TestFlight, then the store

**Priority:** release blocker

## What

1. Join the Apple Developer Program and create the App Store Connect record under the final bundle ID.
2. Signing, plus a CI upload using an App Store Connect API key.
3. Internal TestFlight for Jack and a few testers.
4. External TestFlight, through Beta App Review: a rehearsal of the full review.
5. Public launch on iOS. The [macOS target](../v1-must-haves/macos-target.md) joins the same record.

The work includes the App Review demo account and short reviewer notes.

## Decision

Decided by Jack 2026-11-03 (C6): **iOS first, through TestFlight**, with macOS as a fully supported target; Android and
web are removed. C10 keeps end-to-end runs local, so CI builds and uploads but does not run the simulator suite.

## Why

- SOURCED ([Apple 4.2](https://developer.apple.com/app-store/review/guidelines/)): an app must be more than a
  repackaged website.
- From memory, to verify: internal TestFlight needs no review, external does, and apps with a login must give App
  Review demo credentials.

## Recommendation

Claude's recommendation: Xcode automatic signing with an API key in CI. TestFlight builds point at a separate Firebase
project (for example `screendead-vice-tracker-beta`), so testers never write into production and the bundle-ID change
can be rehearsed. Creating that project is Jack's.

**Effort:** L

**Revenue impact:** The gate to all store revenue.

**Depends on:** [name and bundle ID](name-and-bundle-id.md); versioning (done: `CHANGELOG.md`, `tools/build-version.sh`, the Release workflow); [account deletion](in-app-account-deletion.md); [privacy policy](privacy-policy-and-labels.md); [backend hardening](backend-hardening.md); `no-license-file-anywhere` (fixed in PR #34: proprietary LICENSE) (queue 1c, C8).

**Needs Jack:** yes — Will he pay for the Developer Program, who are the beta testers, and do TestFlight builds use
production Firebase or a separate beta project?
