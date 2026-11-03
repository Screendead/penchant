# No crash reporter, analytics, performance monitor, or logging call exists anywhere

**Severity:** medium

`pubspec.yaml` declares no `firebase_crashlytics`, `firebase_analytics`, `firebase_performance`, `sentry` or comparable package, and the committed platform config shows none was half-wired: the iOS plist sets `IS_ANALYTICS_ENABLED` to false.

A repo-wide grep for `print` and `debugPrint` across `lib/` returns nothing, and the single logging entry in `pubspec.lock` is a transitive dependency no app code imports. No crash report, session trace, performance trace or diagnostic line is captured for any build on any platform.

## Evidence

- `pubspec.yaml:38` — `firebase_core: ^4.12.1\n  cloud_firestore: ^6.7.1\n  firebase_auth: ^6.5.6\n  fl_chart: ^1.2.0\n  intl: ^0.20.3\n  flutter_riverpod: ^3.1.0\n  riverpod_annotation: ^4.0.0`
- `ios/Runner/GoogleService-Info.plist:19` — `<key>IS_ANALYTICS_ENABLED</key>\n\t<false></false>`
- **`grep -rn "print(\|debugPrint(" lib/`** → `(no matches)`
- `pubspec.lock:571` — `logging:\n    dependency: transitive\n    description:\n      name: logging`
