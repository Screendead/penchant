#!/usr/bin/env bash
# Renders the Apple Watch app's screens (ios/PenchantWatch) and complications on this Mac as PNGs, from canned
# states, at the 45 mm and 40 mm screens' point sizes, scale 2: tools/watch-render.sh <dir>. A look without a
# watchOS simulator; a Mac render lacks the watch's chrome and font metrics.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
dir=${1:?usage: tools/watch-render.sh <dir>}
mkdir -p "$dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The complications' view, switching on RenderFamily (tools/watch-render/complications.swift), without @main.
sed -e 's/@Environment(\\.widgetFamily) private var family/var family: RenderFamily = .accessoryCircular/' \
  -e '/^@main/,$d' "$root/ios/PenchantWatchWidgets/Complications.swift" >"$tmp/WatchComplications.swift"
grep -q 'var family: RenderFamily' "$tmp/WatchComplications.swift"
swiftc -o "$tmp/watch-render" \
  "$root/ios/PenchantWatch/WatchModel.swift" "$root/ios/PenchantWatch/WatchTheme.swift" \
  "$root/ios/PenchantWatch/HabitList.swift" "$root/ios/PenchantWatch/WatchStore.swift" \
  "$tmp/WatchComplications.swift" \
  "$root/tools/watch-render/complications.swift" "$root/tools/watch-render/main.swift"
"$tmp/watch-render" "$dir" "$root/assets/fonts"
