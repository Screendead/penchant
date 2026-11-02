# Give every build a unique version, a tag and a changelog entry

**Priority:** release blocker

## What

- Use semantic versioning in `pubspec.yaml`, starting the pre-release line at 0.x.
- Take the build number from CI so every upload is unique.
- Tag each release in git (`v1.0.0`).
- Keep a CHANGELOG.md that feeds the store's "What's New" text.
- Show the version on the About page.

## Why

- SOURCED (repo): the pubspec says `version: 1.0.0+1`, there are no tags and there is no changelog.
- SOURCED (register): Android's fallback version differs from the pubspec version.
- From memory, to verify: both stores reject an upload whose build number is not higher than the previous one.

## Options

- **A.** Manual pubspec bumps, with a hand-written changelog entry in each PR.
- **B.** The version lives in the pubspec, CI injects the build number via `--build-number`, a release workflow creates the tags, and the changelog comes from PR titles.
- **C.** A full release tool such as release-please. More machinery than a solo app needs.

## Recommendation

Claude's recommendation, not a decision: **B.** It removes the "forgot to bump" failure at upload time, and the human-readable version stays a deliberate choice.

**Effort:** S

**Revenue impact:** A release prerequisite. It also makes support workable, because a user's version identifies the exact code they are running.

**Depends on:**
- [`version-never-incremented-and-no-tags`](../../tech-debt/repo-docs-and-release-hygiene/version-never-incremented-and-no-tags.md)
- [`no-changelog-or-release-notes`](../../tech-debt/repo-docs-and-release-hygiene/no-changelog-or-release-notes.md)
- [`android-version-fallback-diverges-from-pubspec`](../../tech-debt/platform-and-delivery-config/android-version-fallback-diverges-from-pubspec.md)
- `production-deploys-with-no-quality-gate` (fixed in PR #25)

**Needs Jack:** no
