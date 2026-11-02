# Gradle falls back to hardcoded 1 and 1.0 when local.properties lacks Flutter's injected keys

**Severity:** low

app/build.gradle reads the version code and version name from android/local.properties, a machine-local gitignored file, falling back to the literals 1 and 1.0. The local.properties present in this checkout contains only sdk.dir and flutter.sdk, so a direct Gradle invocation here produces those fallbacks, and 1.0 does not match pubspec.yaml's 1.0.0 format, a divergence baked into the fallback itself.

## Evidence

- `android/app/build.gradle:16` — `def flutterVersionCode = localProperties.getProperty("flutter.versionCode")\nif (flutterVersionCode == null) {\n    flutterVersionCode = "1"\n}`
- `android/app/build.gradle:21` — `def flutterVersionName = localProperties.getProperty("flutter.versionName")\nif (flutterVersionName == null) {\n    flutterVersionName = "1.0"\n}`
- `android/local.properties:1` — `sdk.dir=/Users/jacklusher/Library/Android/sdk\nflutter.sdk=/opt/homebrew/share/flutter`
