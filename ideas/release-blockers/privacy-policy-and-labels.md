# Publish a privacy policy, App Privacy labels and the Health and Calendar disclosures

**Priority:** release blocker

## What

Write a data inventory and use it for the hosted privacy policy (linked from the listing and from Settings > Privacy),
the App Store Connect App Privacy answers, and a `PrivacyInfo.xcprivacy` if the SDK manifests are not enough. The
inventory has two halves:

- **Synced to Firestore:** email, display name, photo URL, uid, and the user's own logs (vices, timestamps,
  quantities, triggers, context, notes).
- **Never leaves the device:** everything read from Apple Health and Calendar, and everything the insights engine
  derives.

## Why

- SOURCED ([5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/)): a privacy policy is required in App
  Store Connect and in the app, and it must confirm that third parties with access to data give equal protection.
- SOURCED ([HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)): "You
  must also provide a privacy policy for any app that uses the HealthKit framework," and information from HealthKit
  must not go to a third party without express permission.
- SOURCED (5.1.3(i), (ii)): health data may not be used for advertising, marketing or data mining, the specific health
  data collected must be disclosed, and personal health information may not be stored in iCloud.
- SOURCED (repo): no privacy manifest under `ios/Runner`, and the Settings > Privacy row 404s.
- INFERENCE, to verify with a source: under GDPR Art. 9, alcohol, drug and tobacco logs may be special-category health
  data for UK and EU users, which would need explicit consent.

## Options

- **A.** A generator-based policy (Termly, iubenda).
- **B.** A short hand-written policy built on the two halves above, plus a one-screen consent step.
- **C.** B plus a paid legal review.

## Recommendation

Claude's recommendation: **B** for 1.0, **C** before 1.1 adds Health and the paywall. "Health and calendar data never
leave your phone" is both the safest reading of Apple's rules and the trust line in the listing.

**Effort:** M

**Revenue impact:** A release blocker, and the base of the trust positioning.

**Depends on:** [support pages](support-about-and-legal-pages.md); [crash reporting](../v1-must-haves/crash-reporting-and-analytics.md); [Apple Health](../insights/apple-health-correlation.md); [`four-named-routes-dead-end-at-not-found`](../../tech-debt/navigation-and-unreachable-ui/four-named-routes-dead-end-at-not-found.md).

**Needs Jack:** yes — Which legal entity, contact address and data-controller details go in the policy, and is a paid
legal review in budget before 1.1?
