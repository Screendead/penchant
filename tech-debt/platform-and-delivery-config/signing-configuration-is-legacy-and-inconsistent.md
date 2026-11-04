# iOS uses the deprecated identity string with a hardcoded team while macOS has no team at all

**Severity:** low

Three iOS build configurations hardcode a personal development team rather than leaving it to local or CI configuration (left as is: it is the release team).

The macOS project has no development team setting anywhere and mixes automatic provisioning on the main Runner target with manual provisioning on a secondary target that names no team or profile, so that target cannot codesign as committed. LastUpgradeCheck is still stamped at Xcode 15.1 on both platforms.

## Evidence

- `ios/Runner.xcodeproj/project.pbxproj:494` — `DEVELOPMENT_TEAM = 8N575942RT;`
- `macos/Runner.xcodeproj/project.pbxproj:285` — `ProvisioningStyle = Manual;`
