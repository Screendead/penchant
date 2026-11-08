# Feed the insights engine from more sources on the device

**Priority:** insights (built free, Jack 2026-11-08: "add them all to the roadmap")

## What

Each source becomes another daily series for the [insights engine](insights-engine.md), read on the device and kept
there. Grouped by what stands in the way.

**No blocker (free team, no outside service):**

- **Health beyond sleep and heart rate:** State of Mind (iOS 18), workouts, mindful minutes, cycle tracking. Same
  channel and permission flow as [Apple Health](apple-health-correlation.md).
- **Places:** Core Location visits, clustered on the device into the user's own places (home, work, a named spot).
  Opt-in, the most sensitive source; coordinates never leave the device.
- **Daylight:** sunrise, sunset and day length computed on the device from a rough location. No network.
- **Music:** recently played from Apple Music (MusicKit), as a rough mood and context signal. Only for Apple Music
  users.
- **Reminders and Focus:** EventKit reminders beside [Calendar](calendar-integration.md); Focus only says whether a
  Focus is on (`INFocusStatusCenter`), not which.

**Blocked or costly:**

- **Journaling Suggestions** (workouts, places, people contacted, music, photos the user picks for an entry): needs
  the `com.apple.developer.journal.allow` entitlement. UNVERIFIED whether the free team can sign it; probe it the way
  HealthKit was probed (HANDOVER, queue item 7).
- **Weather:** WeatherKit needs the paid team. A free outside service would see a rough location, which breaks "it
  stays on your device"; ask Jack before using one.
- **Screen Time:** the Family Controls entitlement needs the paid team and Apple's approval, and the DeviceActivity
  API reports through an extension that cannot hand raw usage to the app.
- **Spending:** FinanceKit is US-only and needs Apple's approval.

## Recommendation

Build the unblocked group in the order listed, each as one small PR after the engine and Health (queue item 7). Probe
Journaling Suggestions before planning it. Leave the blocked three until there is a paid team or Jack asks.

**Effort:** M each for the unblocked sources.

**Needs Jack:** only for weather's outside service, and the paid team for the blocked group.
