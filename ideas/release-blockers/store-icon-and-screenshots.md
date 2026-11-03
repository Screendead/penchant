# Make a final icon and generate store screenshots from the e2e harness

**Priority:** release blocker

## What

Produce the final icon once the brand is chosen: the iOS 1024 asset and the macOS icon set. Capture store screenshots
automatically with an `integration_test` run on iOS Simulators and on macOS, against the emulators (`--project
demo-*`), seeded with a realistic demo journal (several vices, triggers, a few weeks of entries, and insight cards),
at each required device size.

## Why

- SOURCED (register): the only icon source is `assets/icon.webp`.
- INFERENCE: an emulator-seeded screenshot run is mostly the e2e harness the repo already requires before merge, so it
  pays twice. Insight cards need weeks of plausible data; generating it is the only honest way to show them.
- From memory, to verify: App Store Connect requires screenshots for the largest iPhone size class, and a Mac listing
  needs its own.

## Options

- **A.** A hand-made icon and manual screenshots: quick, stale after every UI change.
- **B.** A designed icon and automated screenshots, framed and captioned by a tool such as fastlane frameit.
- **C.** Generated icon candidates, with B.

## Recommendation

Claude's recommendation: **B.** The icon is a taste call for Jack and waits on the brand. Seed demo data that is
obviously illustrative (round numbers, neutral vices like coffee) so screenshots do not read as encouraging (1.4.3).

**Effort:** M

**Revenue impact:** Direct, through store conversion.

**Depends on:** [brand name](brand-name.md).

**Needs Jack:** yes — Who makes the icon: Jack, a commissioned designer, or generated candidates for him to pick from?
