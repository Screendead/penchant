# The app name and description are still the flutter-create scaffold text outside the Dart code

**Severity:** medium

main.dart sets the MaterialApp title to Vice Tracker, and nothing outside lib/ reflects that name. The Android home-screen label is tracker, and the PWA name, short name, browser tab title and apple-mobile-web-app-title are all tracker, with the manifest description and the HTML meta description both reading A new Flutter project.

pubspec.yaml's description carries the same scaffold text and README.md repeats it, so the package identity fields were never revisited after scaffolding.

## Evidence

- `android/app/src/main/AndroidManifest.xml:3` — `android:label="tracker"`
- `web/manifest.json:2` — `"name": "tracker",`
- `web/manifest.json:8` — `"description": "A new Flutter project.",`
- `web/index.html:26` — `<meta name="apple-mobile-web-app-title" content="tracker">`
- `web/index.html:32` — `<title>tracker</title>`
- `pubspec.yaml:2` — `description: "A new Flutter project."`
