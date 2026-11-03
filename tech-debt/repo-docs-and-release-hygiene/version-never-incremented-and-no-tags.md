# The pubspec version is unchanged since the first commit and the repository has no tags

**Severity:** high

No git tag exists anywhere in history, so there is no way to correlate a shipped build with the commit that produced it, and every build the app could report identifies itself as 1.0.0 build 1. App Store Connect rejects an upload whose build number it has already received, so a second TestFlight upload from this tree fails until the number is raised.

## Evidence

- `pubspec.yaml:19` — `version: 1.0.0+1`
- **`git log -p --follow -- pubspec.yaml`** → `+version: 1.0.0+1`
- **`git tag -l`** → (no output — no tags exist)
