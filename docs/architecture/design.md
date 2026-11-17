# Design: tokens, fonts, habit colours, report, app lock

UI direction: Day Dial (`r6-ui-direction`). Its mock-up and Flutter notes are in
`docs/pitch/mockups/ui-overhaul/day-dial/` on `master` (`index.html`, `tokens.json`, `notes.md`, the stills; landed
per `r10-pitch-branches` C; the source branch is to be archived as the tag `archive/design/ui-overhaul-day-dial`).
`lib/design/tokens.json` is the source of truth (it began as the mock-up's export; that copy is outdated);
`tokens.dart` mirrors it (light and dark colours, type scale, spacing, radii, sizes, motion durations and curves), and
`test/design_tokens_test.dart` fails on drift. `appTheme(Brightness)` (`lib/design/app_theme.dart`) builds both
`ThemeData`s; `MaterialApp` takes `themeMode` from `appearanceProvider` (the startup screen in `lib/bootstrap.dart`
follows the system). Chrome is ink on paper (paper on ink in dark): `primary` and the selection roles are ink; no
`ColorScheme` role takes a habit colour, since the five icon hues mean habits only. Two `ThemeExtension`s,
`DialColors.of(context)` and `DialType.of(context)`, supply what `ColorScheme` lacks: habit colours `data` and their
text colours `dataInk`, `spoke`, `clear`/`clearInk` (the clear day), `scrim`, `wedgeInk`, the bead treatment; and the
display and Mono styles. Both fall back to the ambient brightness's tokens when a test's bare `ThemeData` lacks them.
Screens take colours from the theme, never literals (`test/theme_test.dart` checks `lib/` outside `lib/design/`).

Fonts: Red Hat Display (titles), Text (everything else) and Mono (changing numbers), variable fonts bundled with their
OFL in `assets/fonts/`, so nothing is fetched at runtime; `FontWeight` drives `wght`. `main()` registers the OFL
(`registerFontLicence`, `lib/design/font_licence.dart`) so the licence page under Settings > About lists it with the
packages'. Every theme style sets tabular figures. Widget tests render in the test font unless they load the assets
(`theme_test.dart` does).

A habit's colour is its creation order, oldest first, archived included (equal `createdAt`s by id):
`habitMarks(vices)` (`lib/design/habit_mark.dart`) maps each vice id to a `HabitMark`: `slot` picks `data1`-`data5`;
`style` is filled for habits 1-5, a ring for 6-10, a dotted ring for 11-15, then repeats. Pass `viceListProvider`'s
full list, not the unarchived one, or archiving recolours later habits. Computed on device; stores nothing.

**Report** (`lib/report/`, round 24 "A one-page report for a doctor or partner"). Settings > Make a report
(`ReportOptionsPage`, `/settings/report`) picks habits (none by default), 1, 3, 6 or 12 calendar months ending today
(`reportWindow`), and Include notes (off: no entry notes, day notes or free-text tags). Make report reads the journal
through `Account.fetchData`, the export's server read, so offline it fails. `buildReport`
(`report_data.dart`) is the only place options are applied: a document `fetchData` could not open still holds
`sealed`, so its entries and habits are counted (`lockedEntries`, `lockedHabits`) and left out; the PDF builder sees
only `ReportData`. Totals are Trends' arithmetic: `bucketTotals` per day over the window, `bucketTotals` and
`bucketUnits` per week from the week holding its first day (the region's first weekday, short end weeks labelled),
`hourProfile` (its last 90 days, which the page says). Nothing from Health is read. `report_pdf.dart` lays it out with
the pure-Dart `pdf` package: A4, or Letter in `letterRegions`; black on white; a month grid per calendar month,
three to a row; one `MultiPage` per habit, so one habit over three months is one page (`test/report_test.dart`);
no author in the metadata. `pdf` reads only a variable font's default instance, so it embeds static cuts in
`assets/fonts/pdf/`, made by `tools/pdf-fonts.py` (fontTools). `ReportPreviewPage` shows the pages through
`printing`'s `Printing.raster` (system PDF rendering, a plugin with a `Package.swift`), says the shared file is
outside the encryption for good, then writes the PDF to `penchant-report/` in the temporary directory and shares
that path; leaving the page deletes the folder (macOS answers when a service is chosen, before it reads the file).
`ReportOutput` (`reportOutputProvider`) holds raster, write, share and discard for tests to fake.
`test/report_render_test.dart` writes sample PDFs, their pages through poppler's `pdftoppm`, and both screens.

**App lock** (`lib/app_lock/`, off by default; built for a pitch, `r2-applock`). Settings > App lock turns on only
after one successful Face ID, Touch ID or passcode check; the choice is per device in shared_preferences (`appLock`),
read by `startApp` before `runApp` (`appLockSavedProvider`, false in tests) so a locked journal never flashes.
`AppLockGate`, in `MaterialApp.builder` above the menu bar, the rejected-writes banner and `RecoveryKeyGate`, keeps
the app mounted but covered (no semantics, focus, pointer or tickers) while locked or obscured. It locks at launch and on a return after `AppLock.grace` (1 minute) hidden or paused; inactive alone
(the system's own auth sheet) starts no clock. On iOS inactive obscures with a plain cover for the app switcher; the
Mac does not (it turns inactive on every focus change). The lock screen asks once by itself, then waits for its button.
A device with no passcode left opens and turns the lock off. The macOS Log menu drops its habits while covered. Native
side: `DeviceAuth` (LocalAuthentication's device-owner policy) in `ios/Runner/AppDelegate.swift` and
`macos/Runner/MainFlutterWindow.swift`, channel `com.screendead.penchant/device_auth`; no plugin.
