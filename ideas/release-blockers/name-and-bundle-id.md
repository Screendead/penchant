# Lock the public name and bundle ID before the first TestFlight upload

**Priority:** release blocker

## What

Choose the public name, the App Store subtitle, the bundle ID and the Android applicationId. Then make every identity string match: the `MaterialApp` title, the iOS display name, the Android label, the web manifest, the pubspec description and the README. Register the new bundle ID as an app in Firebase and regenerate the platform config.

## Why

- SOURCED (repo): the in-app title is "Vice Tracker" (`lib/main.dart:38`), while `CFBundleDisplayName` is "Tracker" and `CFBundleName` is "tracker". The iOS bundle ID and the Android applicationId are both `com.screendead.tracker.tracker`, with the segment doubled by the scaffold. The pubspec description is still "A new Flutter project."
- From memory, to verify: an App Store Connect record's bundle ID cannot change once a build has been uploaded.
- INFERENCE: "Tracker" is impossible to find in search. "Vice" is a hook, but it can read as moralising or glamorising, which matters for 1.4.3.

## Options

- **A.** Keep "Vice Tracker".
- **B.** A short, distinct brand plus a descriptive subtitle (for example "\<Brand\>: Habit & Vice Log"), with a bundle ID of the form `com.screendead.<brand>`.
- **C.** A neutral wellness name ("Tally", "Intake" and similar) that leaves "vice" out.

## Recommendation

Claude's recommendation, not a decision: **B**, decided before any TestFlight upload, screenshots or marketing. A rename after launch costs reviews and search momentum. Check trademark and App Store name availability before committing.

**Effort:** S

**Revenue impact:** Direct, through search and store conversion. It is a release prerequisite because of the bundle-ID lock-in.

**Depends on:** [positioning](positioning-and-target-user.md); [`placeholder-app-identity-strings`](../../tech-debt/platform-and-delivery-config/placeholder-app-identity-strings.md); [`macos-firebase-config-carries-the-ios-test-bundle-id`](../../tech-debt/platform-and-delivery-config/macos-firebase-config-carries-the-ios-test-bundle-id.md). Registering the app in the Firebase console is a production action, so Jack does it.

**Needs Jack:** yes — What is the app called, and what is its bundle ID?
