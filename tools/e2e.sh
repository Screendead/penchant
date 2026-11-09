#!/usr/bin/env bash
# Runs integration_test/ on an iOS Simulator, or as a macOS app, against the
# Auth and Firestore emulators under a demo-* project. Exits with the test
# run's status.
#
#   tools/e2e.sh                 # every file in integration_test/, in one build (all_test.dart)
#   tools/e2e.sh integration_test/smoke_test.dart
#   E2E_DEVICE=<udid> tools/e2e.sh
#   E2E_FLUTTER_ARGS='--dart-define=WRITE_TIMEOUT_MS=5000' tools/e2e.sh   # extra flutter test arguments
#   E2E_DEVICE=macos tools/e2e.sh   # all_test.dart as a macOS app; several named files get one flutter test each
set -euo pipefail
source "$(dirname "$0")/emulator-env.sh"

require_free_ports
boot_simulator

if [ "$E2E_DEVICE" = macos ] && [ "$#" -gt 1 ]; then
  # Flutter's macOS runner cannot relaunch the app for a second file in one `flutter test`.
  printf -v args ' %q' "$@"
  script="tools/e2e-macos-each-file.sh$args"
else
  targets="${*:-integration_test/all_test.dart}"
  script="flutter test $targets -d $E2E_DEVICE --dart-define=USE_FIREBASE_EMULATORS=true${E2E_FLUTTER_ARGS:+ $E2E_FLUTTER_ARGS}"
fi
exec firebase emulators:exec \
  --project "$E2E_PROJECT" \
  --only auth,firestore \
  "$script"
