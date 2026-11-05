# Generate store screenshots from the e2e harness

**Priority:** release blocker

## What

The icon is done: Jack picked candidate 38 (the Today radar's coloured segments with its spokes, on a light
background) on 2026-11-05 from the `mockup/icon-sheet` sheet, and it ships from `assets/icon.svg` and
`assets/icon-macos.svg`. What is left: capture store screenshots automatically with an `integration_test` run on iOS Simulators and on macOS, against the emulators (`--project
demo-*`), seeded with a realistic demo journal (several vices, triggers, a few weeks of entries, and insight cards),
at each required device size.

## Why

- INFERENCE: an emulator-seeded screenshot run is mostly the e2e harness the repo already requires before merge, so it
  pays twice. Insight cards need weeks of plausible data; generating it is the only honest way to show them.
- From memory, to verify: App Store Connect requires screenshots for the largest iPhone size class, and a Mac listing
  needs its own.

## Options

- **A.** A hand-made icon and manual screenshots: quick, stale after every UI change.
- **B.** A designed icon and automated screenshots, framed and captioned by a tool such as fastlane frameit.
- **C.** Generated icon candidates, with B.

## Recommendation

Claude's recommendation: **B.** Seed demo data that is
obviously illustrative (round numbers, neutral vices like coffee) so screenshots do not read as encouraging (1.4.3).

**Effort:** M

**Revenue impact:** Direct, through store conversion.

**Depends on:** the brand, Penchant (`r2-brand`, [name and bundle ID](name-and-bundle-id.md)), for the captions.

**Needs Jack:** no
