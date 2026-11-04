# Errors reach only the device's own log; nothing reports them off the device

**Severity:** medium

`lib/errors/report_error.dart` is the one sink for caught errors, uncaught errors (`FlutterError.onError`, `PlatformDispatcher.onError`) and failed providers (`ReportProviderErrors`). It writes to the device log and nowhere else: `pubspec.yaml` declares no `firebase_crashlytics`, `firebase_analytics`, `firebase_performance`, `sentry` or comparable package, and the iOS plist sets `IS_ANALYTICS_ENABLED` to false.

A failure on a user's device is seen only by someone reading that device's log with Console.app or `flutter logs`. No crash report, session trace or performance trace leaves any build. Which reporter, if any, is Jack's open call `r2-crash`.

## Evidence

- `lib/errors/report_error.dart:8` — `void reportError(Object error, StackTrace? stack, {required String context}) {`
- **`grep -nE 'crashlytics|analytics|performance|sentry' pubspec.yaml`** → `(no matches)`
- `ios/Runner/GoogleService-Info.plist:19` — `<key>IS_ANALYTICS_ENABLED</key>\n\t<false></false>`
