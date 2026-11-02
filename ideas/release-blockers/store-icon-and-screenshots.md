# Make a final icon and generate store screenshots from the e2e harness

**Priority:** release blocker

## What

Produce a final icon once the name is chosen: the iOS 1024 asset, an Android adaptive foreground and background, and a real maskable PWA icon. Capture store screenshots automatically with an `integration_test` run on iOS Simulators. It runs against the emulators (`--project demo-*`), seeds them with demo data, and captures each key screen at the required device sizes.

## Why

- SOURCED (register): the only icon source is `assets/icon.webp`. There is no adaptive icon, the maskable icons are byte-identical copies, and the documented seed script writes documents that crash the parser.
- INFERENCE: an emulator-seeded screenshot run is mostly the end-to-end harness the repo already requires before merge, so the work pays twice.
- From memory, to verify: App Store Connect requires screenshots for its current largest iPhone size class.

## Options

- **A.** A hand-designed icon and manual screenshots. Quick the first time, and stale after every UI change.
- **B.** A designed icon and automated screenshots, framed and captioned by a tool such as fastlane frameit.
- **C.** A generated or stock icon, with B.

## Recommendation

Claude's recommendation, not a decision: **B.** The automation keeps the screenshots honest as the UI changes. The icon is a taste call for Jack, and it waits on the name.

**Effort:** M

**Revenue impact:** Direct, through store conversion. Screenshots are the main thing a browsing user judges.

**Depends on:**
- [name and bundle ID](name-and-bundle-id.md)
- [`seed-script-writes-documents-that-crash-the-parser`](../../tech-debt/firebase-data-layer/seed-script-writes-documents-that-crash-the-parser.md)
- [`no-adaptive-icon-for-api-26`](../../tech-debt/platform-and-delivery-config/no-adaptive-icon-for-api-26.md)
- [`maskable-icons-are-byte-identical-copies`](../../tech-debt/platform-and-delivery-config/maskable-icons-are-byte-identical-copies.md)

**Needs Jack:** yes — Who makes the icon (Jack, a commissioned designer, or generated candidates for him to pick from)?
