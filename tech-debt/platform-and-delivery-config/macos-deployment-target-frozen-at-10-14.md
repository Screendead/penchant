# macOS still targets Mojave while iOS was raised to 15.0 in the recent upgrade

**Severity:** low

macos/Podfile pins the osx platform to 10.14 and all three build configurations set the same deployment target, unchanged since the platform was added. The iOS deployment target moved from 13.0 to 15.0 in the 2026 upgrade commit.

macOS 10.14 has been outside Apple's security-update window for years and predates Swift, SwiftUI and sandbox APIs the current Flutter and Firebase SDK generation may assume.

## Evidence

- `macos/Podfile:1` — `platform :osx, '10.14'`
- `macos/Runner.xcodeproj/project.pbxproj:564` — `MACOSX_DEPLOYMENT_TARGET = 10.14;`
