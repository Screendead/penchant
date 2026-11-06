#!/usr/bin/env bash
# Prints the flutter build flags for the current commit: the version from
# pubspec.yaml and the number of commits on HEAD as the build number.
# Usage: flags=$(tools/build-version.sh) && flutter build ipa $flags
# In zsh, ${=flags}: zsh does not word-split $flags, and Flutter takes the pair as one build name.
# Not `flutter build ipa $(tools/build-version.sh)`: a failed substitution expands to nothing and the build still runs.
set -euo pipefail
cd "$(dirname "$0")/.."

name=$(sed -n 's/^version: *\([0-9][0-9.]*\)\(+.*\)\{0,1\}$/\1/p' pubspec.yaml)
[ -n "$name" ] || { echo "no version in pubspec.yaml" >&2; exit 1; }
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
  echo "shallow clone: fetch full history for a correct build number" >&2
  exit 1
fi
echo "--build-name=$name --build-number=$(git rev-list --count HEAD)"
