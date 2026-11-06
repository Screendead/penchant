# Changelog

Newest first. Each release gets a `## [X.Y.Z]` section matching the `version:` in `pubspec.yaml`; the release workflow
publishes that section as the GitHub release notes, and it is the source for the App Store "What's New" text. Add a
line under `[Unreleased]` in the PR that makes the change, worded for the person using the app. Seeded from the merged
pull request titles (`gh pr list --state merged`).

## [Unreleased]

### Added

- Logging works with no signal: an offline banner, a "Not yet synced" mark on entries the server has not received,
  and an empty day offline says the device may not have it rather than calling it clear.
- A change saved offline that the server later refuses (for example, an entry for a vice deleted on another device)
  is named in a banner at the top of the screen until you dismiss it, instead of disappearing without a word.
  That holds across a restart too: a change made offline and refused after you closed the app is named the next
  time it opens and syncs.
- Account Settings exports your data as CSV and JSON, deletes the account with everything in it, resends the
  verification email and changes the email address; sign-in has a password-reset link. Signing out clears this
  device's copy of your data, and asks first if entries have not synced (#54).
- The app builds for the Mac, on macOS 12 Monterey or later (#47).

### Changed

- The app is called Penchant, and it says "habit" wherever it said "vice". Exports are named `penchant-…`.
- Penchant installs as a new app (`com.screendead.penchant`) on iPhone and Mac: an earlier build stays beside it until
  you delete it, and you sign in again in the new one. Your data is unchanged.
- A new look: paper and ink colours from the app icon, the Red Hat typefaces built into the app, and light and
  dark themes that follow your device's appearance setting (the app was dark only).
- Every colour meets the WCAG 2.2 AA contrast minimum in both themes: text fields, outlined buttons, sheet handles
  and the smoothing slider's track have a clearly visible edge, the usage graph's raw line and the Today chart's
  rings are darker, and dark mode's secondary text is a little brighter. The time picker shows which of hour and
  minute is selected and draws its typed-in fields with an edge, and a button focused from the keyboard has an ink
  ring (paper in dark).
- A new app icon: the Today chart's shape, one colour per segment, on a light background.
- The history list opens an entry by tapping the row only; the separate pencil button is gone.
- A screen that cannot load its data says why and offers Retry, instead of spinning forever; so does the app when it
  cannot start. Save and delete errors read the same plain wording on every screen, and every error is written to the
  device log.
- Saving, editing, deleting, adding or editing a vice and archiving no longer report a slow connection as a failure:
  after ten seconds the screen closes and says the change will sync. Buttons stay disabled while their change is in flight.
- Dates, times and numbers follow your device's region: day order and digit grouping, with one format for each
  across the Today menu, the graph, the history list and the date fields. The history list follows the device's
  24-Hour Time setting. The app is in English.
- Manage Data's activity counts work offline: each row counts what this device holds and says so, rather than going
  blank. Your Vices also shows the offline banner.
- An archived vice's history stays reachable: its Manage Data row opens it, marked "Archived", and the Graph lists it
  last as "(archived)" instead of opening on it.
- A signed-in launch no longer flashes the sign-in screen while the saved session loads.
- Today and the Graph move on at midnight, and on returning to the app the next day, instead of staying on yesterday.
- The activity editor shows changes made elsewhere while it is open, until you edit that field.
- The Graph keeps its vice, range and smoothing when you switch tabs, and loads only while it is showing.

### Fixed

- Vices created before archiving existed now show on Today and in the record dialog, so you can log against them.
- The usage graph puts each entry on the right day, and shows the whole of today, across a daylight-saving change.
- The usage graph: weekly view counts weeks back from today, so the newest point is a whole week rather than a
  short remainder that looked like a drop; the smoothing control, its caption and the average always agree; the
  lines no longer dip below zero; and axis labels no longer repeat or overlap, at any text size. Long vice names on
  the Today chart are cut short instead of running into their neighbours.
- Today keeps vice names readable at large text sizes: a title that does not fit drops its amount before its name is
  cut, and when any name is cut, a key below the chart lists every vice with its total. The chart's titles no longer
  run into the rows above and below it; at the largest sizes, when there is no room left for the chart, the key
  takes its place.
- Today shows every vice's amount: when a title has no room for its amount, the key below the chart lists every
  vice with its total, instead of that amount appearing nowhere. The radar's rings are labelled in whole numbers,
  without the "0.0" that sat at its centre.

## [0.1.0] - Unreleased

### Added

- Day navigation, activity history, an activity editor and a usage graph (#28).
- Today shows bars below three vices and the radar from three up, a quiet "clean day" state, a queued-save message
  when a save is waiting to sync, and an 8 second Undo (#36).
- Vices can be archived: an archived vice disappears from recording and from Today but keeps its history (#12).
- The app shows its version and build number under Settings > About.

### Changed

- Firestore rules require a positive quantity, vice names of at most 60 characters, and an activity's vice to belong
  to the person logging it (#33).
- Firestore rules fixed for activity Undo and delete, and for cross-account overwrites (#27).
- Flutter and dependencies upgraded; iOS 26 build stabilised (#12, #13).
- Android, web, Cloud Functions and hosting removed; the app targets iOS and macOS (#34).

### Internal

- Quality gates in CI, pinned Flutter and actions (#25); end-to-end tests on an iOS Simulator against the Firebase
  emulators (#29); handover notes, the tech-debt register and the product ideas backlog (#24, #26, #35).

### Earlier history

- Add vice (#3) and a homepage layout rework (#2).
