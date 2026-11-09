---
name: release
description: Version numbers, build numbers and cutting a release of the tracker app (CHANGELOG, version bump, Release workflow). Use when building an IPA, bumping the version, or releasing.
---

`version:` in `pubspec.yaml` is the user-facing semantic version (0.x until the first App
Store release); its `+N` is a placeholder. The build number of any shipped build is the commit count on `master`, so it
rises with every merge and App Store Connect never sees a repeat. Shipped builds take both from `tools/build-version.sh`,
never by hand:

```bash
tools/build-version.sh flutter build ipa   # appends --build-name=0.1.0 --build-number=212 as two arguments (needs full history, not a shallow clone)
tools/build-version.sh                     # no arguments: prints the flags; in zsh expand them with ${=flags}
```

To release: add the PR lines under `## [Unreleased]` in `CHANGELOG.md` as you go; in a release PR bump `version:`,
rename that section to `## [X.Y.Z] - <date>`, and merge. Then run the Release workflow
(`gh workflow run release.yml --repo Screendead/penchant`) on `master`: it re-runs the checks, tags `vX.Y.Z` and
publishes that changelog section as the release notes (`tools/changelog-section.sh X.Y.Z` prints it). It refuses a
version that already has a release. The app shows `version (build)` under Settings > About.
