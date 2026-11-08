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
- SOURCED (repo, built 2026-11-06): the iOS app embeds `RecaptchaEnterpriseSDK.framework`, which firebase_app_check's
  Swift package depends on although the app never activates a reCAPTCHA provider. Its `PrivacyInfo.xcprivacy`
  declares crash data, device ID, performance data and product interaction (linked, app functionality, no
  tracking), so Xcode's privacy report lists them beside Firebase's own manifests. The macOS build has no such
  framework.
- INFERENCE, to verify with a source: under GDPR Art. 9, alcohol, drug and tobacco logs may be special-category health
  data for UK and EU users, which would need explicit consent.

- SOURCED (`lib/crypto/`, built): the journal's names, units and triggers are sealed on the device, but timestamps,
  quantities and amounts are collected in plaintext, so the label and any wording must say "we can see when and how
  much you log, not what".
- SOURCED (`lib/firebase_init.dart`): the Crashlytics forwarder drops `FlutterErrorDetails.informationCollector` but
  sends each exception whole. A scrubbing rule is still needed so that no exception message or reason carries a decrypted
  name, unit or trigger; otherwise the end-to-end claim is false.

## Options

- **A.** A generator-based policy (Termly, iubenda).
- **B.** A short hand-written policy built on the two halves above, plus a one-screen consent step.
- **C.** B plus a paid legal review.

## Recommendation

Claude's recommendation: **B** for 1.0, **C** before 1.1 adds Health and the paywall. "Health and calendar data never
leave your phone" is both the safest reading of Apple's rules and the trust line in the listing.

**Effort:** M

**Revenue impact:** A release blocker, and the base of the trust positioning.

**Depends on:** [support pages](support-about-and-legal-pages.md); [crash reporting](../v1-must-haves/crash-reporting-and-analytics.md); [Apple Health](../insights/apple-health-correlation.md).

**Needs Jack:** no call left. No privacy policy for now (`r2-privacy`, Jack, 2026-11-06); the legal details wait until and unless he decides to sell.
