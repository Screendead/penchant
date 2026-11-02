#!/usr/bin/env bash
# Runs integration tests through tools/e2e.sh while a local HTTP server turns
# each screenshot() call in integration_test/support.dart into an
# `xcrun simctl io <udid> screenshot <dir>/<name>.png` of the e2e simulator.
#
#   tools/e2e-screenshots.sh <dir> [integration_test/<file>.dart]
set -euo pipefail
source "$(dirname "$0")/emulator-env.sh"

out_dir="$(mkdir -p "$1" && cd "$1" && pwd)"
shift
port=9600

boot_simulator
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $port is in use." >&2
  exit 1
fi

python3 -I - "$port" "$E2E_DEVICE" "$out_dir" <<'PY' &
import http.server, re, subprocess, sys
port, device, out_dir = int(sys.argv[1]), sys.argv[2], sys.argv[3]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.strip("/")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            self.send_response(400)
            self.end_headers()
            return
        path = f"{out_dir}/{name}.png"
        ok = subprocess.run(
            ["xcrun", "simctl", "io", device, "screenshot", path]
        ).returncode == 0
        self.send_response(200 if ok else 500)
        self.end_headers()
        print(path if ok else f"failed: {path}", flush=True)

    def log_message(self, *args):
        pass

http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT

# e2e.sh splices its arguments into the flutter test command line, so the
# define rides along with the targets.
E2E_DEVICE="$E2E_DEVICE" "$REPO_ROOT/tools/e2e.sh" "${@:-integration_test}" \
  "--dart-define=E2E_SCREENSHOT_URL=http://localhost:$port"
