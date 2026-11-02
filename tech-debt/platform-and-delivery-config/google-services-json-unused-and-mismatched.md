# The committed google-services.json is read by no build step and names a different package

**Severity:** medium

No Google Services Gradle plugin is applied anywhere: the root build.gradle has no buildscript block, and neither settings.gradle nor app/build.gradle declares the plugin, so nothing reads the file during a build. Its declared package is com.screendead.tracker while the app's namespace and applicationId are com.screendead.tracker.tracker, so applying the plugin later would fail with a no-matching-client error rather than start working.

Firebase functions on Android only because firebase_options.dart independently hardcodes an Android options block carrying the same app registration, leaving the JSON file redundant with and out of sync with the config that matters.

## Evidence

- `android/app/google-services.json:12` — `"package_name": "com.screendead.tracker"`
- `android/app/build.gradle:27` — `namespace = "com.screendead.tracker.tracker"`
- `android/app/build.gradle:38` — `applicationId = "com.screendead.tracker.tracker"`
- `lib/firebase_options.dart:57` — `appId: '1:573818595550:android:fd0917cdce8d8f022cba4f',`
