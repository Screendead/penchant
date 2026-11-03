# E2EE timing tools

- `E2EE_BENCH=1 flutter test test/bench/e2ee_bench_test.dart`: JournalCipher in pure Dart on the host
  (the path `flutter test` takes; the app never does, since `nativeAesGcm` refuses the Dart fallback).
- `swift tools/bench/cryptokit_bench.swift`: CryptoKit AES-256-GCM at the blob sizes, with no platform
  channel, plus PBKDF2 for scale.
- `channel_bench_test.dart`: JournalCipher through cryptography_flutter's platform channel to CryptoKit,
  as the app runs it. The tracker's macOS target did not build on this branch, so it runs in a bare host:

  ```bash
  flutter create --platforms=macos --project-name e2ee_channel_bench <dir>
  cd <dir>
  flutter pub add cryptography:^2.9.0 cryptography_flutter:^2.3.4 'dev:integration_test:{"sdk":"flutter"}'
  # macOS deployment target 12.0 in macos/Podfile, its post_install, and Runner.xcodeproj
  mkdir -p lib/crypto integration_test
  cp <repo>/lib/crypto/{native_aes,journal_cipher}.dart lib/crypto/
  cp <repo>/tools/bench/channel_bench_test.dart integration_test/bench_test.dart
  flutter test integration_test/bench_test.dart -d macos
  ```

  A copy lives in `~/development/tracker-tools/e2ee_channel_bench`.
