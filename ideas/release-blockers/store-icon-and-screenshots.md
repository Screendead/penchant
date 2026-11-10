# Frame the store screenshots and add the Mac set

**Priority:** release blocker

## What

The icon ships (candidate 38, picked 2026-11-05, from `assets/icon.svg` and `assets/icon-macos.svg`). The iPhone
screenshots are generated: `integration_test/store_screenshots_test.dart` seeds a demo journal (`test/store_journal.dart`:
Coffee, Tea, Chocolate, Fizzy drink, 120 days with triggers, and Health values that give Insights cards) and captures
Today, Trends, Insights and the Log fan at 1320x2868 (iPhone 18 Pro Max, 6.9"), committed under
`docs/pitch/round-14/store-screenshots/`. What is left: a Mac listing's screenshots (`tools/e2e-screenshots.sh` needs a
simulator; the Mac app would need a window capture and has no Health, so Insights shows "Available on iPhone"), and
framing and captions (Option B's frameit or similar).

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

**Effort:** S

**Revenue impact:** Direct, through store conversion.

**Depends on:** the brand, Penchant (`r2-brand`), for the captions.

**Needs Jack:** no
