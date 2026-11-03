# The app name and description are still the flutter-create scaffold text outside the Dart code

**Severity:** medium

main.dart sets the MaterialApp title to Vice Tracker, and nothing outside lib/ reflects that name: the iOS bundle name is tracker and its display name Tracker, and the macOS product name is tracker.

pubspec.yaml's description carries the same scaffold text and README.md repeats it, so the package identity fields were never revisited after scaffolding.

## Evidence

- `ios/Runner/Info.plist:10` — `<string>Tracker</string>` (CFBundleDisplayName)
- `ios/Runner/Info.plist:18` — `<string>tracker</string>` (CFBundleName)
- `macos/Runner/Configs/AppInfo.xcconfig:8` — `PRODUCT_NAME = tracker`
- `pubspec.yaml:2` — `description: "A new Flutter project."`
