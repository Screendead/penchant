# The macOS GoogleService-Info.plist registers the iOS RunnerTests bundle id

**Severity:** medium

macos/Runner/GoogleService-Info.plist declares a BUNDLE_ID ending in RunnerTests, the identifier of the iOS test target, and its GOOGLE_APP_ID is tagged platform ios, as is macos/firebase_app_id_file.json. The macOS app's own product bundle identifier, set in AppInfo.xcconfig and used by every build configuration including the main Runner target, is a different string.

The plist is wired into that target's Resources build phase, so it ships in the built app, and the macOS build initializes Firebase under an app identity never registered for that bundle id. CI builds the macOS app unsigned but never launches it, so the drift is dormant rather than actively breaking a pipeline.

## Evidence

- `macos/Runner/GoogleService-Info.plist:11` — `<key>BUNDLE_ID</key>\n\t<string>com.screendead.tracker.tracker.RunnerTests</string>`
- `macos/Runner/Configs/AppInfo.xcconfig:11` — `PRODUCT_BUNDLE_IDENTIFIER = com.screendead.tracker.tracker`
- `macos/Runner.xcodeproj/project.pbxproj:323` — `7B97340733F85F87E42265E2 /* GoogleService-Info.plist in Resources */,`
- `macos/Runner/GoogleService-Info.plist:28` — `<string>1:573818595550:ios:c170a56c255f4b002cba4f</string>`
- `macos/firebase_app_id_file.json:4` — `"GOOGLE_APP_ID": "1:573818595550:ios:c170a56c255f4b002cba4f",`
- `lib/firebase_options.dart:46` — `iosBundleId: 'com.screendead.tracker.tracker.RunnerTests',`
