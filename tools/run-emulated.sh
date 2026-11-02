#!/usr/bin/env bash
# Launches the app on an iOS Simulator against the Auth and Firestore
# emulators for manual checks. The Emulator UI is at http://localhost:4000.
# Data lives only as long as this script; quitting flutter stops the emulators.
#
#   tools/run-emulated.sh
#   E2E_DEVICE=<udid> tools/run-emulated.sh
set -euo pipefail
source "$(dirname "$0")/emulator-env.sh"

require_free_ports
boot_simulator

firebase emulators:start --project "$E2E_PROJECT" --only auth,firestore &
emulators=$!
trap 'kill "$emulators" 2>/dev/null; wait "$emulators" 2>/dev/null || true' EXIT

for _ in $(seq 1 120); do
  if curl -sf "http://localhost:4400/emulators" >/dev/null; then break; fi
  if ! kill -0 "$emulators" 2>/dev/null; then
    echo "Emulators exited before becoming ready." >&2
    exit 1
  fi
  sleep 1
done

flutter run -d "$E2E_DEVICE" --dart-define=USE_FIREBASE_EMULATORS=true "$@"
