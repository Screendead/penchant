# The same tool-regenerated file is gitignored on iOS and committed on macOS

**Severity:** medium

`ios/.gitignore` excludes its `GeneratedPluginRegistrant`, while the macOS equivalent is tracked. Every plugin change on macOS therefore produces a diff in a generated file that iOS never surfaces.

## Evidence

- `ios/.gitignore:28` — `Runner/GeneratedPluginRegistrant.*`
- **`git ls-files macos/Flutter/GeneratedPluginRegistrant.swift`** → `macos/Flutter/GeneratedPluginRegistrant.swift`
