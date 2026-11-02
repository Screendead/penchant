# Ship a signed native iOS build through TestFlight before the public launch

**Priority:** release blocker

## What

Ship in stages:

1. Join the Apple Developer Program and create the App Store Connect record.
2. Set up signing, plus a CI upload using an App Store Connect API key.
3. Run internal TestFlight for Jack and a few testers.
4. Run external TestFlight, which goes through Beta App Review. It doubles as a rehearsal of the full review.
5. Launch publicly on iOS.

The work also includes the App Review demo account and reviewer notes that explain the harm-reduction intent.

## Why

- SOURCED ([Apple 4.2](https://developer.apple.com/app-store/review/guidelines/)): an app must be more than a repackaged website. CI builds and deploys only the web target today, so the store build has to be the native Flutter iOS target.
- SOURCED (repo): the version is `1.0.0+1` and there is no LICENSE (HANDOVER J5).
- From memory, to verify: internal TestFlight needs no review and external TestFlight does. Apps with a login must give App Review demo credentials.

## Options

- **A.** iOS first through TestFlight. [Android](../growth-later/android-release.md) follows once its build is fixed.
- **B.** iOS and Android at the same time. Twice the review surface, and the Android build fails today.
- **C.** A web PWA sold through Stripe, outside the stores. It avoids review, but loses store discovery and IAP, and the PWA has no offline shell.

## Recommendation

Claude's recommendation, not a decision: **A.** iOS is the closest platform to shippable, the merge gate already runs on iOS Simulators, and the competitor evidence is iOS-centric. External TestFlight brings any 1.4.3 or 5.1.1 objections to the surface before the real submission. Use Xcode automatic signing with an API key in CI, rather than a heavier setup.

**Effort:** L

**Revenue impact:** The gate to all store revenue.

**Depends on:**
- [name and bundle ID](name-and-bundle-id.md)
- [versioning](versioning-and-changelog.md)
- [account deletion](in-app-account-deletion.md)
- [privacy policy](privacy-policy-and-labels.md)
- [backend hardening](backend-hardening.md)
- [`no-license-file-anywhere`](../../tech-debt/repo-docs-and-release-hygiene/no-license-file-anywhere.md)

**Needs Jack:** yes — Will he pay for Apple Developer Program membership, who are the beta testers, and should TestFlight builds use production Firebase or a separate beta project?
