# Give every build a unique version, a tag and a changelog entry

**Priority:** release blocker

## What

- Semantic versioning in `pubspec.yaml`, with pre-release builds on 0.x.
- CI supplies the build number (`--build-number`), so every TestFlight and Mac upload is unique.
- A git tag per release (`v1.0.0`).
- A CHANGELOG.md that feeds "What's New".
- The version on the About page.

## Why

- SOURCED (repo): the pubspec says `version: 1.0.0+1`; there are no tags and no changelog.
- From memory, to verify: App Store Connect rejects an upload whose build number is not higher than the last one for
  that version, and the iOS and macOS builds of one app record each need their own increasing build numbers.

## Options

- **A.** Manual bumps and a hand-written changelog line per PR.
- **B.** The version lives in the pubspec, CI injects the build number, a release workflow tags, and the changelog is
  drafted from PR titles.
- **C.** A release tool such as release-please. More machinery than a solo app needs.

## Recommendation

Claude's recommendation: **B.** It removes the "forgot to bump" failure at upload time and keeps the user-facing
version a deliberate choice.

**Effort:** S

**Revenue impact:** A release prerequisite; it also makes support workable.

**Depends on:**
- [`version-never-incremented-and-no-tags`](../../tech-debt/repo-docs-and-release-hygiene/version-never-incremented-and-no-tags.md)
- [`no-changelog-or-release-notes`](../../tech-debt/repo-docs-and-release-hygiene/no-changelog-or-release-notes.md)

**Needs Jack:** no
