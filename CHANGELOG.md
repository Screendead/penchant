# Changelog

Newest first. Each release gets a `## [X.Y.Z]` section matching the `version:` in `pubspec.yaml`; the release workflow
publishes that section as the GitHub release notes, and it is the source for the App Store "What's New" text. Add a
line under `[Unreleased]` in the PR that makes the change, worded for the person using the app. Seeded from the merged
pull request titles (`gh pr list --state merged`).

## [Unreleased]

### Added

- Settings › Reminder sends one quiet notification a day at a time you choose; it is off until you turn it on, and
  only then asks to send notifications. Press and hold it to log something, or tap Clean day to close it.
- On a day of more than 48 entries, Today's dial draws each busy hour as one arc labelled with its count, coloured by
  habit, instead of a heap of beads. Tap it to open the entry nearest that time; with VoiceOver it opens the hour's
  latest entry, and its actions list every entry.
- End-to-end encryption is on. The first launch makes your journal key, keeps it in iCloud Keychain, and seals your
  habits' names, units and categories, and any entry triggers, in the background; dates and amounts stay readable
  to the server. Save the recovery key (Settings › Account, or the card Today shows a week in): a device without
  the key asks for it before opening your journal.
- Settings › Appearance lets you choose Light or Dark, or keep matching your phone; each device remembers its own
  choice. Export my data is now one tap from Settings, as well as under Account.
- The Mac window opens at 1200 x 780, wide enough for Trends to sit beside Today, and reopens at the size and place
  you left it. It narrows to 390 pt, where the phone layout returns.
- Pages open with a soft fade-through instead of sliding in. A drag on the dial too short to change the day eases
  it back instead of snapping. With Reduce Motion on, pages and a day change fade instead (the old day's entries
  fade out before the new day's fade in).
- A habit's history opens with a Last 30 days card: the total, a 24-hour ring of when it happened, and the
  three hours that hold the most.
  you left it. It narrows to 390 pt; below 900 pt the phone layout returns.

### Fixed

- With large text, the offline and refused-change banners no longer push Today off the screen: each stops at a third
  of the screen and scrolls, and the sync status beside the menu stops growing at twice its size.
- A device that opens on "Unlock your journal" because iCloud Keychain has not yet brought the key from your
  other device now checks again every few seconds and when you return to the app, and opens the journal by itself
  once the key arrives.
- The recovery key box on the unlock screen is one line high where the key fits, instead of leaving an empty
  second line under it.
- Switching between Sign in and Create account is smooth: Email and Password stay put and keep what you typed,
  while the password confirmation and checklist ease in or out in step with the tab instead of the screen jumping.
- iOS AutoFill fills the email as well as the password on the sign-in screen, and offers to save the email and
  password after you sign in, so a changed email reaches the saved password.

### Added

- A daily server check for data left behind by guest accounts that expired: Firebase removes an unused guest account
  after 30 days but not its habits and entries. For now the check only records what it would remove; nothing is
  deleted.
- Habits can be stored sealed: a habit's name and unit travel in one encrypted field, with dates, ids and entry
  amounts left plain so every list and chart works as before. The rules accept both shapes; sealing stays off until
  the encryption work is complete (until then everything is written as before).
- The journal key service, still switched off: on first need the app makes your journal key, keeps it in iCloud
  Keychain so your other Apple devices get it with nothing to do, and stores on the server only the key's id and a
  copy that only your recovery key opens. A device without the key asks for the recovery key, or starts a new
  journal. Deleting your account also deletes that record.
- Groundwork for end-to-end encryption: the code to make a key for your account, keep it in iCloud Keychain, seal and
  open data with it, and write it out as a recovery key. The app does not use it yet, so nothing is encrypted.
- Once end-to-end encryption is on, the first launch with your key seals the habits, and the triggers of
  entries, you created before it, in the background, and removes their readable copies from the server. It waits
  for a connection, picks up where it left off if interrupted, and Settings shows its progress.
- A recovery key screen, under Account settings and offered on Today a week in: the key in large groups with Copy
  and Share, then a check that you typed its last group back. A device without the journal key will ask for it before
  any screen opens, the entry field points to a mistyped character, and the page offers Sign out and a lost-key path
  to a new journal. Switched off until the whole encryption stack and the key service land.
- A guest journal is erased 30 days after it starts unless it is saved to an email. From day 20 Today says how many
  days are left, and in the last 3 days a sheet asks once a day; both lead to saving it to an email.
- Recording or editing an entry can say what was going on: the habit's usual triggers as one-tap chips, areas of
  life with more specific options inside, or your own words, which become a choice once used three times. It is
  optional, and the Log fan still logs one in one tap. The history list shows each entry's triggers.
- Each habit has a category (alcohol, caffeine, nicotine, cannabis, food, gambling or other), picked in the habit
  editor. Habits made before this get one guessed from their name the first time the app opens, which you can change.
- A new account starts with a short welcome: pick the habits to keep a journal of from a list (Alcohol, Coffee,
  Cigarettes, Vape, Cannabis, Energy drinks, Sweets, Gambling, or one you name yourself), read the one-line
  disclaimer, and log a first entry if you like. An account that already has habits never sees it.
- A monthly server job stores each habit's typical amount over the last three months, and the Day Dial sizes beads
  against it, falling back to the shown day's median until it has run.
- Quantities can be decimals, such as 1.5 drinks or 0.25 hours, in the record dialog and the entry editor, written
  with your region's decimal mark. Totals, charts and the CSV export (a new `amount` column) count them exactly.
- Start without an account: the sign-in screen opens a guest journal, and Account Settings saves it to an email and
  password later with every entry kept. Signing out of a guest journal erases it
  from the server and the device, after a warning, and refuses offline rather than leave part of it behind.
- Crashes and errors are reported to the developer through Firebase Crashlytics, with the error and where it
  happened, never your habits or amounts.
- On the Mac, Cmd-1 to Cmd-9 log one of the first nine habits in Today's order, with the same Undo as the +; a Log
  menu in the menu bar lists them by name. A hardware keyboard on an iPad gets the same keys on Today.
- Changing day slides the day's name in from the side it lies on, and the dial's sweep fades out once the hand has
  gone round instead of vanishing.
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
- On a window 900 pt wide or more (a Mac, or an iPad on its side), Trends sits beside Today as a pane instead of a
  sheet: the dial and tallies on the left, with the Log button under them, and the chart on the right. A day picked on
  the chart moves Today's dial to it. Resizing across 900 pt keeps the day and habit you picked. The left and right
  arrow keys step through days, except on the chart, where they move its cursor.

### Changed

- Holding a habit in the Log fan opens an amount sheet instead of the record dialog: the habit's name at the top, a
  large amount with − and + to step it (or type a decimal), and one button that says what it will log and when.
  Editing an entry uses the same amount stepper.
- An entry can carry up to ten triggers, picked from the starter tree (Social, Feeling, Work, Body, Routine, Place,
  Craving) or typed in; exports include them as a "triggers" column.
- On a clear day the dial's every-3-hours spokes fade with the others, as in the design, so the clear dial is
  quieter; the 00, 06, 12 and 18 labels still give the time.
- Trends by week shows whole weeks only: the range rounds down to a whole number of weeks (30 days shows 28, 90 shows
  84, a year shows 364), so the oldest point no longer reads low from holding a few days.
- Habits and each habit's history are in the Day Dial style: Habits lists active habits, then archived ones, with
  each habit's colour and entry count; a habit's history groups its entries by day with a daily total. Archive and
  Edit habit live on the history page.
- Deleting an entry is a swipe left on its history row, and every delete (history and editor alike) shows the bar
  with an 8-second Undo that puts the entry back as it was.
- Sign-in and account creation are one screen with a Sign in / Create account switch, and the password rules tick
  off as you type. Settings and Account Settings use the new card style with a round back button, and Settings
  shows your email and the app's version at a glance. Moving through rows, the sign-in switch and sliders with a
  keyboard now shows a clear ring around the one in focus.
- Today matches its design: the Penchant icon and name at the top open a menu with Habits, Settings and whether
  your entries have synced, in place of the side drawer, and a pill beside them says Synced, Syncing or Offline. The
  dial, the five tallies, the Log button and the Trends peek all fit on one iPhone screen, the light theme lifts its
  cards and sheets with soft shadows, a habit at zero fades in its row, and the icons are the design's line icons.
- Today is a 24-hour dial: each entry is a coloured bead at the time it happened, sized against your usual amount
  that day, with the time beside it on a quiet day and the clock hand on today. Under it, a row per habit gives the
  day's total and a + that logs one now, with eight seconds to Undo. The Log button opens a fan of your habits: tap
  one to log it now, hold it for the amount and time. Tap a bead to edit its entry; change the day with the arrows, a
  swipe across the dial or the calendar, which goes back as far as you like and marks the days each habit was
  logged. The radar and bar charts are gone.
- Trends replaces the Graph tab: a sheet that peeks under Today with a sparkline of a habit and its daily average,
  and pulls up over the dial. Pick a habit (archived ones last), 7, 30 or 90 days or a year, by day or by week, and
  how many days or weeks the average line spans; it gives the total, the average and the peak, and when in the day
  the habit happens. Drag across the chart to read a day, and tap one to open its dial. The Log button sits on the
  sheet's edge. Chart dates are spaced to fit every month's name. From a keyboard the arrow keys move along the chart
  and Enter opens the day; VoiceOver reads the day under the cursor and swipes up or down to move it.
- The app is called Penchant, and it says "habit" wherever it said "vice". Exports are named `penchant-…`.
- Penchant installs as a new app (`com.screendead.penchant`) on iPhone and Mac: an earlier build stays beside it until
  you delete it, and you sign in again in the new one. Your data is unchanged.
- A new look: paper and ink colours from the app icon, the Red Hat typefaces built into the app, and light and
  dark themes that follow your device's appearance setting (the app was dark only).
- Every colour meets the WCAG 2.2 AA contrast minimum in both themes: text fields, outlined buttons, sheet handles
  and the smoothing slider's track have a clearly visible edge, the usage graph's raw line is darker,
  and dark mode's secondary text is a little brighter. The time picker shows which of hour and
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
- The iPhone and Mac builds get Firebase through Swift Package Manager instead of CocoaPods, which Firebase no
  longer publishes to. Nothing changes in the app.
- On iPhone, the screen shown while the app opens is the app's paper colour, dark in dark mode, instead of white.

### Fixed

- Signing out no longer leaves the last change's Undo bar on the sign-in screen, where its Undo would have acted
  on the account just left.
- Today's sync pill no longer breaks the screen when writes settle and start again faster than its fade.
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
- The rules tests' firebase-tools install no longer breaks its own file-matching code: the minimatch override now
  replaces only the versions the advisory names. A test checks every composite query in the app against
  `firestore.indexes.json`, since the emulators never enforce indexes.
- The Mac app builds for release, as one app for both Apple silicon and Intel Macs.

### Internal

- The decisions page asks round 9: where Archive lives, whether Appearance is a picker, and where Export sits, each
  with the mock-up beside the built screen.
- Test builds against the Firebase emulators no longer turn on App Check, which the emulators never check; the
  App Store build is unchanged.
- The decisions page asks round 8: six calls from the Day Dial and the Mac split view, each with the mock-up beside
  the built app; the round-5 radar calls and the settled e2e-in-CI call are gone.
- The Cloud Functions dev toolchain no longer pulls in the vulnerable `glob` and `minimatch` (an npm override moves the
  unused `rimraf` dependency of `google-gax` to 6.1.4).

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
