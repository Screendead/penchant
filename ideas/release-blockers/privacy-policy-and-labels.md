# Publish a privacy policy, App Privacy labels and a health-data consent step

**Priority:** release blocker

## What

Write a data inventory and use it for three things. The first is a hosted privacy policy, linked from the store listing and from Settings > Privacy. The second is the App Store Connect App Privacy answers, plus the Play Data safety form later. The third is a `PrivacyInfo.xcprivacy` under `ios/Runner/`, if one is needed. Add an explicit consent step for processing consumption logs. The data held today is email, display name, a user-entered photo URL, the uid, and timestamped logs (vice name, unit, quantity).

## Why

- SOURCED ([Apple 5.1.3](https://developer.apple.com/app-store/review/guidelines/)): health data must not be used for advertising, marketing or data mining. Vice logs are plausibly health data.
- SOURCED (repo): there is no privacy manifest under `ios/Runner`, and the Settings > Privacy row dead-ends on a 404.
- Not verified: the market scan did not read 5.1.1(i) (the privacy-policy requirement) or the label pages. Read them before submission.
- INFERENCE, to verify with a source: under GDPR Art. 9, alcohol and tobacco logs may be special-category health data for UK and EU users, which would require explicit consent.

## Options

- **A.** A generator-based policy (Termly, iubenda and similar), hosted on Firebase Hosting.
- **B.** A short, hand-written, app-specific policy ("we store X, never sell it, never advertise with it"), hosted at /privacy, plus a one-screen consent step.
- **C.** B plus a paid legal review.

## Recommendation

Claude's recommendation, not a decision: **B** now, then **C** before the paid tier ships. A short, specific policy is the trust story the competitors' complaints reward. Whether the Flutter and Firebase SDK manifests are enough, or Runner needs its own, should be checked against Apple's current required-reason API docs.

**Effort:** M

**Revenue impact:** A release blocker for both stores, and the base of the "private data" positioning.

**Depends on:** [support, about and legal pages](support-about-and-legal-pages.md); [crash reporting and analytics](../v1-must-haves/crash-reporting-and-analytics.md) (every SDK becomes a label line); [`four-named-routes-dead-end-at-not-found`](../../tech-debt/navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md).

**Needs Jack:** yes — What legal entity name, contact address and data-controller details go in the policy, and should it get a paid legal review?
