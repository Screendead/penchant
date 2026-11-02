#!/usr/bin/env bash
# Runs integration_test/ on an iOS Simulator against the Auth and Firestore
# emulators under a demo-* project. Exits with the test run's status.
#
#   tools/e2e.sh                 # every file in integration_test/
#   tools/e2e.sh integration_test/smoke_test.dart
#   E2E_DEVICE=<udid> tools/e2e.sh
set -euo pipefail
source "$(dirname "$0")/emulator-env.sh"

require_free_ports
boot_simulator

targets="${*:-integration_test}"
exec firebase emulators:exec \
  --project "$E2E_PROJECT" \
  --only auth,firestore \
  "flutter test $targets -d $E2E_DEVICE --dart-define=USE_FIREBASE_EMULATORS=true"
