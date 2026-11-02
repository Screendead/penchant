# The same tool-regenerated file is gitignored on iOS and Android and committed on macOS

**Severity:** medium

`ios/.gitignore` and `android/.gitignore` both exclude their `GeneratedPluginRegistrant`, while the macOS equivalent is tracked. Every plugin change on macOS therefore produces a diff in a generated file that the other two platforms never surface.

## Evidence

- `ios/.gitignore:28` — `Runner/GeneratedPluginRegistrant.*`
- `android/.gitignore:7` — `GeneratedPluginRegistrant.java`
- **`git ls-files macos/Flutter/GeneratedPluginRegistrant.swift`** → `macos/Flutter/GeneratedPluginRegistrant.swift`
