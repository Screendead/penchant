# No Markdown file, workflow, or Firebase config mentions macOS

**Severity:** medium

A repo-wide search across every Markdown file and the workflow and Firebase configs returns zero hits for "macos". CLAUDE.md's commands section documents only `flutter run` with a device picker and a Chrome flag for web, and its architecture section names no platform target at all — the only platform the file mentions anywhere is web — despite `macos/` being a full tracked platform directory with its own Podfile, entitlements, and Firebase config files. The one config mention of macOS in the repository is the `flutter_launcher_icons` `macos:` block at `pubspec.yaml:75`, which is neither a Markdown file nor a workflow or Firebase config.

## Evidence

- **`grep -rin macos --include=*.md /Users/jacklusher/development/tracker/`** → (no output — zero matches)
- `CLAUDE.md:7` — `flutter run                      # device picker; -d chrome for web`
- `pubspec.yaml:75` — `macos:` (flutter_launcher_icons block)
- **`grep -in "ios\|android" CLAUDE.md`** → (no output — zero matches)
- **`grep -nw web CLAUDE.md`** → lines 9, 14, 31 only
