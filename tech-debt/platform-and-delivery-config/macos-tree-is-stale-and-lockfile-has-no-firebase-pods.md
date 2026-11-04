# macos/Podfile.lock resolves no Firebase pods while the committed registrant registers three

**Severity:** high

The lockfile lists only FlutterMacOS and path_provider_foundation, with no cloud_firestore, firebase_auth or firebase_core entry, while macos/Flutter/GeneratedPluginRegistrant.swift imports and registers all three. Git history shows the lockfile was last committed before cloud_firestore and firebase_core were even added to pubspec.yaml, and firebase_auth's registrant import arrived in a later commit that did not touch it.

The macOS project files have not been touched for the platform's pods since 2024-07-27: the 2026 upgrade that moved iOS's deployment target, pod linkage and lockfile changed neither the macOS Podfile nor its lockfile, and the later commits that reached `macos/` changed only the generated plugin registrant. The two lockfiles even record different CocoaPods versions, 1.16.2 for iOS and 1.15.2 for macOS.

## Evidence

- `macos/Podfile.lock:1` — `PODS:\n  - FlutterMacOS (1.0.0)\n  - path_provider_foundation (0.0.1):`
- `macos/Flutter/GeneratedPluginRegistrant.swift:8` — `import cloud_firestore\nimport firebase_auth\nimport firebase_core`
- **`git log --oneline -- macos/Podfile.lock`** → `cceea88 Update macOS specific files and configurations`
- **`git log --oneline -- macos/Podfile macos/Podfile.lock`** → `cceea88 Update macOS specific files and configurations` (2024-07-27)
- `ios/Podfile.lock:1500` — `COCOAPODS: 1.16.2`
- `macos/Podfile.lock:23` — `COCOAPODS: 1.15.2`
