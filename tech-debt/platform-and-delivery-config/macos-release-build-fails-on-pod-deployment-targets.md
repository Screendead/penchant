# `flutter build macos --release` fails because the pods target macOS versions Xcode no longer supports

**Severity:** medium

The macOS release build does not complete. Xcode rejects every pod target whose deployment target is below 12.0, and also the Runner's own "Flutter Assemble" target at 10.15. The macOS app therefore cannot be built for release, although CLAUDE.md lists a macOS debug build as a working command (not re-run here).

The report that prompted this entry described a `lipo` architecture error. That did not reproduce: the build log has no mention of `lipo`, and the failure is the deployment-target one below. The `macos-deployment-target-frozen-at-10-14` entry covers the low deployment target, but not that it now stops the build.

## Evidence

- **`flutter build macos --release`** (Flutter 3.44.7, run 2026-11-03 in a fresh worktree) → `/Users/.../macos/Pods/Pods.xcodeproj: error: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.15, but the range of supported deployment target versions is 12.0 to 27.2.x. (in target 'Firebase' from project 'Pods')`, the same for `FirebaseAuth`, `GoogleUtilities`, `nanopb` and others; `leveldb-library` is 10.13. 42 lines contain `error:`; the output ends `** BUILD FAILED **`.
- Same run → `macos/Runner.xcodeproj: error: ... set to 10.15, but the range ... is 12.0 to 27.2.x. (in target 'Flutter Assemble' from project 'Runner')`.
- `macos/Runner.xcodeproj/project.pbxproj:564`, `:646`, `:696` — `MACOSX_DEPLOYMENT_TARGET = 10.15;`
- `macos/Podfile:1` — `platform :osx, '10.14'`
- The run also rewrote tracked files under `macos/` (Podfile, Podfile.lock, project.pbxproj, scheme, AppDelegate.swift); they were reverted and are not part of this PR.
