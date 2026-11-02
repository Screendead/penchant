#!/bin/sh
# Run by the Runner target's "Strip Firebase plist for emulators" build phase,
# after Copy Bundle Resources. firebase_core configures the native default app
# from GoogleService-Info.plist before Dart runs, which would bind an emulator
# build to the production project. Builds without the define are untouched.
plist="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
for define in $(echo "${DART_DEFINES:-}" | tr ',' ' '); do
  if [ "$(echo "$define" | base64 --decode 2>/dev/null)" = "USE_FIREBASE_EMULATORS=true" ]; then
    if [ -f "$plist" ]; then
      mkdir -p "$DERIVED_FILE_DIR"
      mv -f "$plist" "$DERIVED_FILE_DIR/GoogleService-Info.plist"
      echo "Moved GoogleService-Info.plist out of the app bundle for an emulator build."
    fi
    exit 0
  fi
done
