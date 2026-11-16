#!/usr/bin/env bash
# Compiles what the iPhone and the Apple Watch app share (ios/PenchantWatch/WatchModel.swift) and the
# iPhone's totals for the watch (the WatchConnectivity-free part of ios/Runner/WatchLink.swift) with their
# tests, and runs them on this Mac.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -o "$tmp/watch-model-test" "$root/ios/PenchantWatch/WatchModel.swift" "$root/ios/Runner/WatchLink.swift" \
  "$root/ios/PenchantWidgets/Snapshot.swift" "$root/ios/PenchantWidgets/LogQueue.swift" \
  "$root/tools/watch-model-test/main.swift"
"$tmp/watch-model-test"
