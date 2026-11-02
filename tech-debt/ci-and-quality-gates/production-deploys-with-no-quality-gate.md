# Every push to master deploys to the live channel with no analyze, lint, or test step

**Severity:** high

`firebase-hosting-merge.yml` triggers on every push to master and, if the build succeeds, deploys to the live channel of the production project. Across both workflow files the only Dart commands are `flutter pub get` and `flutter build web`, with no `flutter analyze`, no `custom_lint` run and no `flutter test` anywhere, so a change that compiles but is broken reaches production the moment it lands.

The repository's tier cannot enforce branch protection, so no required status check exists upstream of the trigger either. Nothing in the deployed stack records a runtime failure once it arrives, since there is no crash reporting or logging.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:5` — `on:\n  push:\n    branches:\n      - master`
- `.github/workflows/firebase-hosting-merge.yml:20` — `- name: Install dependencies\n        run: flutter pub get\n      - name: Build in release mode\n        run: flutter build web --release`
- `.github/workflows/firebase-hosting-merge.yml:28` — `channelId: live`
- **`gh api repos/Screendead/tracker/branches/master/protection`** → `{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}`
