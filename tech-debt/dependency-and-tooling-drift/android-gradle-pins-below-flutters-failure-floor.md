# The pinned AGP, Kotlin and Gradle versions are all below the versions Flutter hard-fails on

**Severity:** critical

`android/settings.gradle` pins Android Gradle Plugin 7.3.0 and Kotlin Gradle Plugin 1.7.10, and the wrapper pins Gradle 7.6.3. The Flutter Gradle plugin runs its dependency version checker on every Android Gradle invocation and throws when Gradle is below 8.7.0, AGP below 8.6.0, or the Kotlin plugin below 2.0.0 — all three pins sit below those floors.

CI is unaffected because both workflows build only web, but any Android build or run from this checkout fails immediately, before app code compiles. Because `pubspec.yaml` requires an SDK recent enough to carry the same thresholds, this is not an artifact of one machine's toolchain, and the delegated `compileSdk`, `minSdk` and `targetSdk` values resolve to current numbers that are never consulted.

## Evidence

- `android/gradle/wrapper/gradle-wrapper.properties:5` — `distributionUrl=https\://services.gradle.org/distributions/gradle-7.6.3-all.zip`
- `android/settings.gradle:21` — `id "com.android.application" version "7.3.0" apply false`
- `android/settings.gradle:22` — `id "org.jetbrains.kotlin.android" version "1.7.10" apply false`
- **`cat /opt/homebrew/share/flutter/bin/cache/flutter.version.json`** → `"frameworkVersion": "3.44.7", "channel": "stable", "frameworkCommitDate": "2026-07-17 10:20:17 -0700"`
- **`sed -n '90,110p' .../DependencyVersionChecker.kt`** → `errorGradleVersion: Version = Version(8, 7, 0) ... errorAGPVersion: AndroidPluginVersion = AndroidPluginVersion(8, 6, 0) ... errorKGPVersion: Version = Version(2, 0, 0)`
- **`grep -n "compileSdkVersion: Int\|minSdkVersion: Int\|targetSdkVersion: Int" .../FlutterExtension.kt`** → `val compileSdkVersion: Int = 36 ... val minSdkVersion: Int = 24 ... val targetSdkVersion: Int = 36`
