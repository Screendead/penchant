# Feed the insights engine from more sources on the device

**Priority:** insights (built free, Jack 2026-11-08: "add them all to the roadmap")

## What

Each source becomes another daily series for the [insights engine](insights-engine.md), read on the device and kept
there. Grouped by what stands in the way.

**No blocker (free team, no outside service):**

- **Health beyond sleep and heart rate:** built. Same channel and permission flow as
  [Apple Health](apple-health-correlation.md). Workouts and mindful minutes are built (2026-11-11), as minutes a day;
  cycle tracking is built (2026-11-12) as a phase held fixed in the day-after comparisons, not an outcome; State of
  Mind (iOS 18) is built (2026-11-12) as one valence a day, floored at half the person's own SD of it (Jack, round 16
  `mood-floor` A).
- **Places:** built (2026-11-12, iOS only): Core Location visits clustered on the device into numbered places the
  person can name, sealed on the device, and each habit's share of entries at a place against its share of waking
  time there. Not yet: a "home / work" guess from the hours spent.
- **Daylight:** built (2026-11-12): sunrise, sunset and day length computed on the device from the most-visited
  place or the time zone's city, to whole degrees, no network; day length held fixed where the month terms miss it.
  Not yet: a "dark against light at the same clock hour" comparison.
- **Reminders**, beside
  [Calendar](calendar-integration.md), are built (2026-11-12, iOS only like Calendar): reminders completed a day
  and reminders missed (due that day, not done by its end).

**Blocked or costly:**

- **Journaling Suggestions** (workouts, places, people contacted, music, photos the user picks for an entry): needs
  the `com.apple.developer.journal.allow` entitlement, which the free team cannot sign: probed 2026-11-12 with a
  signed iOS build and provisioning updates, Xcode answered "Cannot create a iOS App Development provisioning profile
  for "com.screendead.penchant". Personal development teams, including "Jack Lusher", do not support the Journaling
  Suggestions capability." Waits for a paid team.
- **Music:** recently played from Apple Music (MusicKit `MusicRecentlyPlayedRequest`), as a rough mood and context
  signal, only for Apple Music users. MusicKit has no entitlement for a build to probe: it is the MusicKit App
  Service ticked on the App ID in Certificates, Identifiers & Profiles (developer.apple.com/help/account/services/musickit),
  which Apple opens only on enrolment ("Once you're enrolled, you'll be able to access additional resources, like
  Certificates, Identifiers & Profiles", developer.apple.com/support/compare-memberships). A personal team has no way
  to tick it, so the app's developer token, and with it recently played, would fail at run time. Set aside
  2026-11-12 until there is a paid team. The one route without it, MediaPlayer's `lastPlayedDate` on library items
  (`NSAppleMusicUsageDescription` only), gives each song's last play alone, not a history, so it cannot say how much
  music a day held or what played before a use; not worth building.
- **Weather:** WeatherKit needs the paid team. A free outside service would see a rough location, which breaks "it
  stays on your device"; ask Jack before using one.
- **Screen Time:** the Family Controls entitlement needs the paid team and Apple's approval, and the DeviceActivity
  API reports through an extension that cannot hand raw usage to the app.
- **Spending:** FinanceKit is US-only and needs Apple's approval.
- **Focus:** `INFocusStatusCenter` says only whether a Focus is on, not which, keeps no history, and can be sampled
  only while the app runs. It needs the Focus Status entitlement (`com.apple.developer.focus-status`), which the free
  team cannot sign: probed 2026-11-12 with a signed iOS build and provisioning updates, Xcode answered "Entitlement
  com.apple.developer.focus-status not found and could not be included in profile." Set aside until there is a paid
  team.

## Recommendation

The unblocked sources are built. Leave the blocked ones (Journaling Suggestions, Music, Weather, Screen Time,
Spending, Focus) until there is a paid team or Jack asks.

**Effort:** M each, once unblocked.

**Needs Jack:** only for weather's outside service, and the paid team for the blocked group.
