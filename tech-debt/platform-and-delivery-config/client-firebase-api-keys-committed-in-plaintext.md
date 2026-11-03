# The client Firebase API key is duplicated between the Apple plists and firebase_options.dart

**Severity:** low

One key is shared by iOS and macOS, and it appears both in each platform-native `GoogleService-Info.plist` and in the generated Dart options. The Android and web keys left the repository with their targets but stay valid in the Firebase project until revoked there. These are client-side SDK keys that identify the project to client apps rather than authentication secrets, so their presence is expected by design, and whether they carry referrer or app restrictions in the Google Cloud console cannot be determined from repository files.

No server-side credential is present anywhere: git history contains no privateKey.json or service-account file, and admin/.gitignore excludes it.

## Evidence

- `ios/Runner/GoogleService-Info.plist:6` — `<string>AIzaSyBpaWDbKfdikRFrvhJpnZPpR6104OpS2gw</string>`
- `lib/firebase_options.dart` — `apiKey: 'AIzaSyBpaWDbKfdikRFrvhJpnZPpR6104OpS2gw',` (the `ios` and `macos` options)
- `admin/.gitignore:1` — `privateKey.json`
- **`git log --all --full-history --oneline -- admin/privateKey.json '**/privateKey.json' '*serviceAccount*'`** → `(no output -- no commit in any branch ever added a file matching these paths)`
