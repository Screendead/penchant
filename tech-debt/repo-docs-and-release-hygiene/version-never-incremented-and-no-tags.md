# The pubspec version is unchanged since the first commit and the repository has no tags

**Severity:** high

CI pushes a fresh production deploy to the live hosting channel on every merge to master with no version gate, no test run, and no analyze run. No git tag exists anywhere in history, so there is no way to correlate a live production build with the commit that produced it, and every build the app could report identifies itself as 1.0.0 build 1 regardless of how many releases have actually shipped.

## Evidence

- `pubspec.yaml:19` — `version: 1.0.0+1`
- **`git log -p --follow -- pubspec.yaml`** → `+version: 1.0.0+1`
- **`git tag -l`** → (no output — no tags exist)
- `.github/workflows/firebase-hosting-merge.yml:4` — `name: Deploy to Firebase Hosting on merge` / `on: push: branches: - master`
- `.github/workflows/firebase-hosting-merge.yml:22` — `run: flutter build web --release` ... `channelId: live`
