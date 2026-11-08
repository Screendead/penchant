#!/usr/bin/env bash
# Runs a build command with the flutter build flags for the current commit: the version from
# pubspec.yaml and the number of commits on HEAD as the build number.
# Usage: tools/build-version.sh flutter build ipa
# The flags are appended as two separate arguments, so no shell word-splitting is involved.
# With no arguments it prints the flags instead, for a shell that splits them itself (bash: $flags;
# zsh does not split $flags, and Flutter then takes the pair as one build name, so use ${=flags}).
set -euo pipefail
cd "$(dirname "$0")/.."

name=$(sed -n 's/^version: *\([0-9][0-9.]*\)\(+.*\)\{0,1\}$/\1/p' pubspec.yaml)
[ -n "$name" ] || { echo "no version in pubspec.yaml" >&2; exit 1; }
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "shallow clone: fetch full history for a correct build number" >&2
  exit 1
fi
number=$(git rev-list --count HEAD)
if [ $# -eq 0 ]; then
  echo "--build-name=$name --build-number=$number"
else
  exec "$@" "--build-name=$name" "--build-number=$number"
fi
