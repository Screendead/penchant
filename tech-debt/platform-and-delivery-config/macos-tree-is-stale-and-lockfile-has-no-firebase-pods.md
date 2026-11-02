# macos/Podfile.lock resolves no Firebase pods while the committed registrant registers three

**Severity:** high

The lockfile lists only FlutterMacOS and path_provider_foundation, with no cloud_firestore, firebase_auth or firebase_core entry, while macos/Flutter/GeneratedPluginRegistrant.swift imports and registers all three. Git history shows the lockfile was last committed before cloud_firestore and firebase_core were even added to pubspec.yaml, and firebase_auth's registrant import arrived in a later commit that did not touch it.

All seven commits that ever touched macos/ cluster within a 3-day window, 2024-07-27 to 2024-07-29, with a shared app-icon change the most recent; the 2026 upgrade that moved iOS's deployment target, pod linkage and lockfile touched zero files there. The two lockfiles even record different CocoaPods versions, 1.16.2 for iOS and 1.15.2 for macOS.

## Evidence

- `macos/Podfile.lock:1` — `PODS:\n  - FlutterMacOS (1.0.0)\n  - path_provider_foundation (0.0.1):`
- `macos/Flutter/GeneratedPluginRegistrant.swift:8` — `import cloud_firestore\nimport firebase_auth\nimport firebase_core`
- **`git log --oneline -- macos/Podfile.lock`** → `cceea88 Update macOS specific files and configurations`
- **`git log --oneline -- macos/`** → `8a4c8f9 Add app icon\nb4eb385 Update dependencies and remove unused code\nf1407c7 \`flutter pub add cloud_firestore\`\nacded99 \`flutter pub add firebase_core\`\n01f4585 \`flutterfire configure\`\ncceea88 Update macOS specific files and configurations\n5ea561b Add macOS specific files and configurations`
- `ios/Podfile.lock:1444` — `COCOAPODS: 1.16.2`
- `macos/Podfile.lock:23` — `COCOAPODS: 1.15.2`
