# Both platforms hardcode a personal development team, and macOS mixes provisioning styles

**Severity:** low

Three iOS build configurations hardcode a personal development team rather than leaving it to local or CI configuration (left as is: it is the release team).

The macOS Runner target hardcodes the same team, and the macOS project mixes automatic provisioning on Runner with manual provisioning on a secondary target that names no team or profile. LastUpgradeCheck is still stamped at Xcode 15.1 on both platforms.

## Evidence

- `ios/Runner.xcodeproj/project.pbxproj:494` — `DEVELOPMENT_TEAM = 8N575942RT;`
- `macos/Runner.xcodeproj/project.pbxproj:285` — `ProvisioningStyle = Manual;`
