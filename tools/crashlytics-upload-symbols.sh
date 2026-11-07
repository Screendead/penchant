#!/bin/sh
# Run by the Runner target's last build phase, "Upload Crashlytics symbols"
# (firebase.google.com/docs/crashlytics/ios/get-started, the Swift Package
# Manager run script). Emulator builds have no GoogleService-Info.plist to read
# the app ID from, and builds without a dSYM have nothing to upload.
for define in $(echo "${DART_DEFINES:-}" | tr ',' ' '); do
  if [ "$(echo "$define" | base64 --decode 2>/dev/null)" = "USE_FIREBASE_EMULATORS=true" ]; then
    echo "Emulator build: no Crashlytics symbols uploaded."
    exit 0
  fi
done
if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
  echo "No dSYM in a ${CONFIGURATION:-} build: no Crashlytics symbols uploaded."
  exit 0
fi
run="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
if [ ! -x "$run" ]; then
  echo "warning: Crashlytics upload script not found at $run; no symbols uploaded."
  exit 0
fi
exec "$run"
