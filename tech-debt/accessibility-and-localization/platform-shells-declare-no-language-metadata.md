# No CFBundleLocalizations on the Apple targets and no lang attribute on the web shell

**Severity:** low

Both Apple platform shells carry only the template development-region variable, neither `Info.plist` sets a `CFBundleLocalizations` array, and both Xcode projects list only `en` and `Base` under `knownRegions`.

The root `html` element in `web/index.html` omits `lang` entirely and `web/manifest.json` has no `lang` or `dir` member, so browsers, screen readers and translation tooling have no declared document language and an installed PWA carries no language signal.

## Evidence

- `ios/Runner/Info.plist:7` — `<key>CFBundleDevelopmentRegion</key>\n\t<string>$(DEVELOPMENT_LANGUAGE)</string>`
- `ios/Runner.xcodeproj/project.pbxproj:239` — `knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);`
- `macos/Runner/Info.plist:5` — `<key>CFBundleDevelopmentRegion</key>\n\t<string>$(DEVELOPMENT_LANGUAGE)</string>`
- `macos/Runner.xcodeproj/project.pbxproj:293` — `knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);`
- `web/index.html:2` — `<html>`
- `web/manifest.json:2` — `"name": "tracker",`
