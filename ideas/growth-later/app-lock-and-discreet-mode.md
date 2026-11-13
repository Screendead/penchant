# Add an app lock and a discreet mode for people journaling sensitive habits

**Priority:** growth / later

## What

Two privacy features under "Your data" in Settings:

- An optional Face ID, Touch ID or passcode lock (Touch ID on the Mac): built behind a draft PR for the round 17 pitch
  (`feat/app-lock`); not merged.
- Discreet mode, not built: neutral notification text, a neutral widget, and an alternate app icon.

## Why

- INFERENCE: someone journaling drinking, cannabis or gambling on a shared or work device needs to trust the app
  before they log honestly every day, and an honest journal is the only one whose insights mean anything.
- SOURCED ([market scan](../market-scan.md)): privacy is the gap the competitors leave open; C15 makes "on the device"
  the positioning.

## Options

- **A.** Both free.
- **B.** Both Pro.
- **C.** The lock only.

## Recommendation

Claude's recommendation: **A, after 1.1.** Charging for privacy undercuts the positioning. Alternate icons beyond the
discreet one could be a Pro cosmetic.

**Effort:** S

**Revenue impact:** Low directly; it supports trust, and so conversion.

**Depends on:** the daily reminder's notification text (`lib/reminder/daily_nudge.dart`), which names no habit; [widgets](widgets-and-shortcuts.md).

**Needs Jack:** no. App lock and discreet mode are both free (`r2-applock`, Jack, 2026-11-06); parked with the store work.
