#!/usr/bin/env bash
# Tests tools/build-version.sh against a scratch repository with two commits.
set -euo pipefail
script=$(cd "$(dirname "$0")" && pwd)/build-version.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/tools"
cp "$script" "$tmp/tools/"
cd "$tmp"
printf 'version: 1.2.3+9\n' > pubspec.yaml
git init -q
git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two

fail() { echo "FAIL: $1" >&2; exit 1; }

[ "$(tools/build-version.sh)" = "--build-name=1.2.3 --build-number=2" ] || fail "print mode"

args=$(tools/build-version.sh printf '[%s]' flutter build ipa)
[ "$args" = "[flutter][build][ipa][--build-name=1.2.3][--build-number=2]" ] || fail "exec mode: $args"

if tools/build-version.sh true 2>/dev/null; then :; else fail "exec mode propagates success"; fi
if tools/build-version.sh false 2>/dev/null; then fail "exec mode must propagate failure"; fi

printf 'nothing\n' > pubspec.yaml
ran=$(tools/build-version.sh echo ran 2>/dev/null || true)
[ -z "$ran" ] || fail "must not run the command without a version"
echo ok
