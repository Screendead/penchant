# The Firebase plugins are an unblocked minor or patch behind, and build_runner, test and a prerelease sit stuck

**Severity:** low

`cloud_firestore`, `firebase_auth` and `firebase_core` each have a clean upgradable path to the newest version and simply have not been moved, one minor or patch behind each.

`test` is stuck at 1.31.0 for the same reason as the riverpod family: its own pubspec allows `analyzer: '>=8.0.0 <13.0.0'`, but riverpod_lint and riverpod_generator's `<9.0.0` cap holds the resolved version back regardless. `build_runner` shows the same upgradable-and-resolvable-stuck symptom at 2.15.1, but its cause was not determined, so a routine `flutter pub upgrade` cannot move either package. `riverpod_analyzer_utils`, pulled in only through the unused lint tooling, resolves to a 1.0.0-dev.8 prerelease in the lockfile.

## Evidence

- **`flutter pub outdated`** → `cloud_firestore *6.7.1 6.8.0 6.8.0 6.8.0 ... firebase_auth *6.5.6 6.5.7 6.5.7 6.5.7 ... firebase_core *4.12.1 4.13.0 4.13.0 4.13.0`
- **`flutter pub outdated`** → `build_runner *2.15.1 *2.15.1 *2.15.1 2.16.0 ... test *1.31.0 *1.31.0 *1.31.0 1.31.2`
- `pubspec.lock:779` — `riverpod_analyzer_utils:\n    dependency: transitive`
- **`flutter pub outdated`** → `riverpod_analyzer_utils *1.0.0-dev.8 *1.0.0-dev.8 *1.0.0-dev.8 1.0.0-dev.11`
