# Log from the home screen, from Siri and into Apple Health

**Priority:** growth / later

## What

Three native integrations, in this order:

1. **Home and lock-screen widgets** showing today's progress, with interactive +1 buttons. This needs a native WidgetKit extension, fed through a package such as home_widget.
2. **App Intents,** so "log a coffee" works from Siri and Shortcuts.
3. **Optional Apple Health write-through** for the types HealthKit supports. INFERENCE, to verify in Apple's docs: these include alcoholic beverages and dietary caffeine.

## Why

- INFERENCE: a widget makes the count visible without opening the app, which is the strongest daily-return mechanic for trackers.
- INFERENCE: Health sync makes the data portable.
- Both strengthen the native-app case under [4.2](https://developer.apple.com/app-store/review/guidelines/).
- SOURCED (5.1.3): HealthKit data may not be used for advertising or data mining, and it needs extra privacy disclosure.

## Options

- **A.** Widgets first, then App Intents, then Health.
- **B.** Health sync first.
- **C.** Defer all native integrations.

## Recommendation

Claude's recommendation, not a decision: **A, after launch.** Start with widgets once quick logging ships, because they reuse its "log one" action. Health goes last because of its review cost. Read Apple's current WidgetKit and HealthKit docs before scoping. Widgets and Health are natural Pro features.

**Effort:** XL

**Revenue impact:** Medium to high. These are classic Pro features, and good material for App Store featuring.

**Depends on:**
- [quick logging](../v1-must-haves/one-tap-quick-logging.md)
- [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md)
- [business model](../monetisation/business-model-and-paywall.md)

**Needs Jack:** no
