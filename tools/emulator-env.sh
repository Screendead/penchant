# Sourced by tools/e2e.sh and tools/run-emulated.sh.

# Must match emulatorProjectId in lib/firebase_init.dart. A demo-* id has no
# live resources, so nothing run under it can reach production.
E2E_PROJECT=demo-tracker
# iPhone 18 Pro. Other simulators on this machine belong to other projects.
E2E_DEVICE="${E2E_DEVICE:-C1CE5005-9E7C-4C4E-8E55-E00A4C671D29}"
EMULATOR_PORTS="8080 9099 9150 4000 4400 4500"

case "$E2E_PROJECT" in
  demo-*) ;;
  *) echo "Refusing to run: $E2E_PROJECT is not a demo-* project." >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

require_free_ports() {
  local busy=0 port
  for port in $EMULATOR_PORTS; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Port $port is in use:" >&2
      lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2
      busy=1
    fi
  done
  if [ "$busy" -ne 0 ]; then
    echo "Stop whatever holds those ports (another emulator run?) and retry." >&2
    exit 1
  fi
}

boot_simulator() {
  if ! xcrun simctl list devices | grep -q "($E2E_DEVICE)"; then
    echo "No simulator with UDID $E2E_DEVICE; set E2E_DEVICE to one from 'xcrun simctl list devices'." >&2
    exit 1
  fi
  # Exit status 149 means already booted.
  xcrun simctl boot "$E2E_DEVICE" 2>/dev/null || true
  xcrun simctl bootstatus "$E2E_DEVICE" -b >/dev/null
}
