#!/usr/bin/env bash
# Run by tools/e2e.sh, inside its emulator session, when E2E_DEVICE=macos.
# Flutter's macOS runner cannot relaunch the app for a second test file in one
# `flutter test` ("Unable to start the app on the device"), so each file gets
# its own. Each file's setUpAll wipes the emulators, so they can share them.
#
# Arguments: test files and directories (default integration_test), plus any
# flags, which every `flutter test` receives. Runs every file, prints a line
# per file, and exits non-zero if any failed.
set -uo pipefail

files=()
flags=()
for arg in "${@:-integration_test}"; do
  if [ -d "$arg" ]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(find "$arg" -name '*_test.dart' | sort)
  elif [ -f "$arg" ]; then
    files+=("$arg")
  else
    flags+=("$arg")
  fi
done
if [ "${#files[@]}" -eq 0 ]; then
  echo "No test files in: ${*:-integration_test}" >&2
  exit 1
fi

summary=()
failed=0
for file in "${files[@]}"; do
  # macOS's bash 3.2 treats an empty array as unset under set -u.
  if flutter test "$file" -d macos --dart-define=USE_FIREBASE_EMULATORS=true \
    ${flags[@]+"${flags[@]}"}; then
    summary+=("PASS $file")
  else
    summary+=("FAIL $file")
    failed=1
  fi
done

printf '%s\n' "${summary[@]}"
exit "$failed"
