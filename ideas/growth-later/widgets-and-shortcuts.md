# Log from the home screen, the Mac menu bar, Siri and Shortcuts

**Priority:** growth / later

## What

Native logging surfaces, in this order:

1. **Home and lock-screen widgets** on iOS (and desktop widgets on macOS) showing today's entries, with interactive
   quick-log buttons. A WidgetKit extension fed through a package such as home_widget.
2. **App Intents,** so "log a coffee" works from Siri, Shortcuts and the Action button, and Shortcuts automations can
   log on a trigger (for example arriving at a bar, if the user builds that).
3. **A macOS menu-bar item** for quick logs at the desk.

Writing alcohol and caffeine to Apple Health is part of [Apple Health](../insights/apple-health-correlation.md).

## Why

- INFERENCE: a widget is the strongest daily-return mechanic for trackers, and every surface that lowers logging
  friction raises the completeness the insights depend on.
- SOURCED ([Apple 4.2](https://developer.apple.com/app-store/review/guidelines/)): native integrations strengthen the
  minimum-functionality case.

## Options

- **A.** Widgets, then App Intents, then the menu bar.
- **B.** App Intents first (no extension target, and Shortcuts users are the quantified-self audience).
- **C.** Defer all.

## Recommendation

Claude's recommendation: **A, after 1.1.** Widgets reuse quick logging's "log one" action. Read Apple's current
WidgetKit and App Intents docs before scoping. Logging surfaces stay free; a widget showing an insight card is Pro.

**Effort:** XL

**Revenue impact:** Medium: retention, and good material for App Store featuring.

**Depends on:** [quick logging](../v1-must-haves/one-tap-quick-logging.md); [macOS target](../v1-must-haves/macos-target.md).

**Needs Jack:** no
