#!/usr/bin/env bash
# Prints the body of the CHANGELOG.md section for a version, e.g. 0.1.0.
# Fails if the section is missing or empty.
set -euo pipefail
cd "$(dirname "$0")/.."

body=$(awk -v v="$1" '
  /^## / { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md | sed '/./,$!d')
[ -n "$body" ] || { echo "CHANGELOG.md has no entries for $1" >&2; exit 1; }
printf '%s\n' "$body"
