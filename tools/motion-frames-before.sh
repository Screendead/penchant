#!/usr/bin/env bash
# tools/motion-frames.sh against <ref>'s app code (default origin/master), for
# the before half of a motion comparison. Restores the working tree after.
#   tools/motion-frames-before.sh <out-dir> [ref]
set -euo pipefail
out=${1:?out dir}
ref=${2:-origin/master}
cd "$(dirname "$0")/.."
saved=$(mktemp -d)
cp -R lib "$saved/lib"
trap 'trash lib && cp -R "$saved/lib" lib && trash "$saved"' EXIT
git diff --name-only "$ref" -- lib | while read -r f; do
  if git cat-file -e "$ref:$f" 2>/dev/null; then git show "$ref:$f" >"$f"; fi
done
tools/motion-frames.sh "$out"
