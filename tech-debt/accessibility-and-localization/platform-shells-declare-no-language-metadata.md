# No CFBundleLocalizations on the Apple targets

**Severity:** low

Both Apple platform shells carry only the template development-region variable, neither `Info.plist` sets a `CFBundleLocalizations` array, and both Xcode projects list only `en` and `Base` under `knownRegions`.

## Evidence

- `ios/Runner/Info.plist:7` — `<key>CFBundleDevelopmentRegion</key>\n\t<string>$(DEVELOPMENT_LANGUAGE)</string>`
- `ios/Runner.xcodeproj/project.pbxproj:240` — `knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);`
- `macos/Runner/Info.plist:5` — `<key>CFBundleDevelopmentRegion</key>\n\t<string>$(DEVELOPMENT_LANGUAGE)</string>`
- `macos/Runner.xcodeproj/project.pbxproj:293` — `knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);`
