# The Android release build type unconditionally uses the debug signing config

**Severity:** high

android/app/build.gradle assigns the debug signing config to the release build type with a self-left TODO acknowledging that no real config exists. No key.properties file and no release signing block exist anywhere in the tree, even though android/.gitignore proactively lists key.properties, keystore and jks patterns as if the setup were planned.

Every release APK or app bundle built from this checkout is signed with the local machine's debug key, which cannot be uploaded to the Play Store.

## Evidence

- `android/app/build.gradle:47` — `buildTypes {\n        release {\n            // TODO: Add your own signing config for the release build.\n            // Signing with the debug keys for now, so \`flutter run --release\` works.\n            signingConfig = signingConfigs.debug\n        }\n    }`
- `android/.gitignore:11` — `key.properties`
- **`git log --oneline --all -- android/`** → `8a4c8f9 Add app icon\n01f4585 \`flutterfire configure\`\n2b5c55c first commit`
- **`git log -1 --format=%ai -- android/app/build.gradle`** → `2024-07-15 20:12:37 +0100`
