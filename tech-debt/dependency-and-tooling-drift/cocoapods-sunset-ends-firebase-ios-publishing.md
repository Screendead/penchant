# Firebase stops publishing to CocoaPods in October 2026, and both Apple builds depend on it

**Severity:** medium

The iOS and macOS targets both pull Firebase through CocoaPods. Firebase's documentation says it will stop publishing new versions to CocoaPods in October 2026, and that CocoaPods itself becomes read-only in December 2026. After October, a Firebase Apple SDK release will not reach the Podfile-based builds, so a `cloud_firestore`, `firebase_auth` or `firebase_core` upgrade that needs a newer native SDK will have to move the Apple builds to Swift Package Manager (Flutter's SPM support) first. Neither platform tree has any Swift Package Manager setup today.

The date was read from Firebase's documentation. Whether the pinned Flutter plugins ship SPM manifests was not checked.

## Evidence

- `https://firebase.google.com/docs/ios/installation-methods` (fetched 2026-11-03) — "Firebase will stop publishing new versions to CocoaPods in October 2026"; CocoaPods "will become read-only in December 2026", after which "new pod versions can no longer be published".
- `ios/Podfile:2` — `platform :ios, '15.0'`; `ios/Podfile.lock` is tracked.
- `macos/Podfile:1` — `platform :osx, '10.14'`; `macos/Podfile.lock` is tracked.
- `ls ios macos | grep -i -E "podfile|Package"` → `Podfile`, `Podfile.lock` for each; no `Package.swift` or Swift package reference.
