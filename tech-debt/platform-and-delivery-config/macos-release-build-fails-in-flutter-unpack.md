# `flutter build macos --release` fails in Flutter's framework unpack step

**Severity:** medium

The macOS release build does not complete. The deployment-target errors that used to stop it are gone (the target
is 12.0 since #47); it now fails in Flutter's own `release_unpack_macos` target, which reports that the FlutterMacOS
framework lacks the `arm64 x86_64` architectures while `lipo` lists exactly those two. The debug build passes, and
CI builds debug only, so nothing gates the release build.

## Evidence

- **`FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO flutter build macos --release`** (Flutter 3.44.7, Xcode 27.2, run
  2026-11-04 on #47's branch) → `Target release_unpack_macos failed: Exception: Binary .../build/macos/Build/Products/Release/FlutterMacOS.framework/Versions/A/FlutterMacOS does not contain architectures "arm64 x86_64".` then `** BUILD FAILED **`; no line names `MACOSX_DEPLOYMENT_TARGET`.
- **`lipo -info`** on that binary → `Architectures in the fat file: ... are: x86_64 arm64`
