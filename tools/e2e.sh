#!/usr/bin/env bash
# Runs integration_test/ on an iOS Simulator, or as a macOS app, against the
# Auth and Firestore emulators under a demo-* project. Exits with the test
# run's status.
#
#   tools/e2e.sh                 # every file in integration_test/, in one build (all_test.dart)
#   tools/e2e.sh integration_test/smoke_test.dart
#   E2E_DEVICE=<udid> tools/e2e.sh
#   E2E_DEVICE=macos tools/e2e.sh   # one flutter test per file, one emulator session
set -euo pipefail
source "$(dirname "$0")/emulator-env.sh"

require_free_ports
boot_simulator

if [ "$E2E_DEVICE" = macos ]; then
  args=""
  if [ "$#" -gt 0 ]; then
    printf -v args ' %q' "$@"
  fi
  script="tools/e2e-macos-each-file.sh$args"
else
  targets="${*:-integration_test/all_test.dart}"
  script="flutter test $targets -d $E2E_DEVICE --dart-define=USE_FIREBASE_EMULATORS=true"
fi
exec firebase emulators:exec \
  --project "$E2E_PROJECT" \
  --only auth,firestore \
  "$script"
