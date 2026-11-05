#!/usr/bin/env bash
# Regenerates the three stills beside index.html with headless Chrome (needs network for Google Fonts).
# Usage: tools/render-stills.sh [chrome-binary]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
chrome="${1:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
shot() {
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$profile" \
    --window-size=1820,1060 --force-device-scale-factor=1 --virtual-time-budget=6000 \
    --screenshot="$here/$1" "file://$here/index.html?bare=1&$2" 2>/dev/null
}
shot stills-light.png 'theme=light&only=1,2,3,5&rec=open'
shot stills-dark.png 'theme=dark&only=1,2,3,5&rec=open'
shot stills-states-dark.png 'theme=dark&only=1,4,6,7&net=off&tap=coffee&sheet=1&auth=up'
shot stills-states-light.png 'theme=light&only=1,4,6,7&net=off&tap=coffee&sheet=1&auth=up'
echo "wrote $here/stills-*.png"
