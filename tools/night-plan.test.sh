#!/usr/bin/env bash
# Compiles ios/PenchantWidgets/NightPlan.swift, which has no ActivityKit, with its tests and runs them.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -o "$tmp/night-plan-test" "$root/ios/PenchantWidgets/NightPlan.swift" "$root/tools/night-plan-test/main.swift"
"$tmp/night-plan-test"
