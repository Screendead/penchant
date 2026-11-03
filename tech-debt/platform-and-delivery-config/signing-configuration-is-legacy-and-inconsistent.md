# iOS uses the deprecated identity string, and both platforms hardcode a personal team

**Severity:** low

Three iOS build configurations set the code-sign identity to iPhone Developer, a name Xcode deprecated in favour of Apple Development though automatic signing still resolves it, and three hardcode a personal development team rather than leaving it to local or CI configuration.

The macOS Runner target hardcodes the same team, and the macOS project mixes automatic provisioning on Runner with manual provisioning on a secondary target that names no team or profile. LastUpgradeCheck is still stamped at Xcode 15.1 on both platforms.

## Evidence

- `ios/Runner.xcodeproj/project.pbxproj:448` — `"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";`
- `ios/Runner.xcodeproj/project.pbxproj:478` — `DEVELOPMENT_TEAM = 8N575942RT;`
- `macos/Runner.xcodeproj/project.pbxproj:285` — `ProvisioningStyle = Manual;`
