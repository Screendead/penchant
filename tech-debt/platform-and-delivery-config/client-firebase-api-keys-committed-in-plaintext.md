# Three client Firebase API keys are duplicated between platform configs and firebase_options.dart

**Severity:** low

One key is shared by Android, one by iOS and macOS, and one by web. The Android and iOS/macOS keys each appear both in their platform-native config file and in the generated Dart options; the web key exists only in firebase_options.dart, since Flutter web has no platform-native Firebase config file to duplicate it into. These are client-side SDK keys that identify the project to client apps rather than authentication secrets, so their presence is expected by design, and whether they carry referrer or app restrictions in the Google Cloud console cannot be determined from repository files.

No server-side credential is present anywhere: git history contains no privateKey.json or service-account file, and admin/.gitignore excludes it.

## Evidence

- `android/app/google-services.json:18` — `"current_key": "AIzaSyDP_pLcKt52V3IVDnECxtWg1mlYtD7pYzA"`
- `ios/Runner/GoogleService-Info.plist:6` — `<string>AIzaSyBpaWDbKfdikRFrvhJpnZPpR6104OpS2gw</string>`
- `lib/firebase_options.dart:47` — `apiKey: 'AIzaSyD2i6JpzJgLvBobdp1R3DjEPiov9cJXISM',` — a repo-wide grep for this key finds only this one line; `web/` holds index.html, manifest.json, favicon.png and icons/, no native Firebase config file
- `admin/.gitignore:1` — `privateKey.json`
- **`git log --all --full-history --oneline -- admin/privateKey.json '**/privateKey.json' '*serviceAccount*'`** → `(no output -- no commit in any branch ever added a file matching these paths)`
