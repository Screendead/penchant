# Local master last synced before the dependency upgrade and the PR #13 merge

**Severity:** medium

`origin/master` has since gained the Flutter and iOS dependency upgrade, the SDK-constraint fix, and the merge commit itself. Anyone checking out local master gets a build configuration three commits stale relative to what CI actually deploys from.

## Evidence

- **`git log master..origin/master --oneline`** → `f79b02e Merge pull request #13 from Screendead/chore/upgrade-flutter-and-all-deps-ios26` / `2344c20 Align Dart SDK constraint with lockfile minimum` / `4fde04d Upgrade Flutter deps and modernize iOS/Firebase build stack`
