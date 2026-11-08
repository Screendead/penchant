#!/usr/bin/env bash
# Compiles ios/Runner/HealthDays.swift, which has no HealthKit, with its tests and runs them.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -o "$tmp/health-days-test" "$root/ios/Runner/HealthDays.swift" "$root/tools/health-days-test/main.swift"
"$tmp/health-days-test"
