# Both workflows configure the Flutter action with a channel and no version

**Severity:** medium

The Flutter action is given the stable channel with no version or version-file input, so each run installs whatever build is tagged stable at that moment. `pubspec.lock` is committed so package resolution is reproducible, but the SDK itself is not: a run today and a run next month can use different toolchains against the same commit, and CI can diverge from the locally installed version with no diff in the repository to explain a build that passes in one place and fails in the other.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:14` — `- uses: subosito/flutter-action@v2\n        with:\n          channel: "stable"`
- `.github/workflows/firebase-hosting-pull-request.yml:16` — `- uses: subosito/flutter-action@v2\n        with:\n          channel: "stable"`
- **`flutter --version`** → `Flutter 3.44.7 • channel stable\nTools • Dart 3.12.2 • DevTools 2.57.0`
