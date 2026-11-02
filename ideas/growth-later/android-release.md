# Release on Android once its build works and is release-signed

**Priority:** growth / later

## What

The Android release follows iOS. It needs:

- a working Android build;
- a release keystore;
- an adaptive icon;
- a Play Console listing, with the Data safety form and account-deletion disclosure.

## Why

- SOURCED (register):
  - Any Android build fails before the app code compiles.
  - Android release builds are signed with the debug keystore.
  - Android is "maintained in name only".
  - The `google-services.json` is unused and does not match.
- SOURCED (market scan gap): Google Play policy was not researched. Play's account-deletion and Data safety rules still need reading.

## Options

- **A.** Android 4–8 weeks after the iOS launch.
- **B.** Android at the same time as iOS.
- **C.** iOS only for now.

## Recommendation

Claude's recommendation, not a decision: **A.** Keep the Android tech debt in the burn-down, so A follows quickly once iOS is stable. Jack's platform decision is HANDOVER J3.

**Effort:** L

**Revenue impact:** Medium. It widens the market, though iOS users usually monetise better in this category (INFERENCE).

**Depends on:**
- [iOS release pipeline](../release-blockers/ios-release-pipeline-and-testflight.md)
- [`android-gradle-pins-below-flutters-failure-floor`](../../tech-debt/dependency-and-tooling-drift/android-gradle-pins-below-flutters-failure-floor.md)
- [`release-builds-are-signed-with-the-debug-keystore`](../../tech-debt/platform-and-delivery-config/release-builds-are-signed-with-the-debug-keystore.md)
- [`android-is-maintained-in-name-only`](../../tech-debt/platform-and-delivery-config/android-is-maintained-in-name-only.md)
- [`no-adaptive-icon-for-api-26`](../../tech-debt/platform-and-delivery-config/no-adaptive-icon-for-api-26.md)
- [`google-services-json-unused-and-mismatched`](../../tech-debt/platform-and-delivery-config/google-services-json-unused-and-mismatched.md)

**Needs Jack:** yes — Android after iOS, or iOS only (HANDOVER J3)?
