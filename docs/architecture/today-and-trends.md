# Navigation, Today, Trends, the split view and reduce motion

**Navigation.** `main.dart` gates on `userProvider`: a user → `Homepage`, an error → `AuthStateFailure`, no event yet
→ `AuthStateLoading` (so a restored session never shows sign-in first), a null user → `Authenticate`. `generateRoute`
maps path segments to a page through `routePage`, a pattern `switch` (`/vices/:viceID/edit`,
`/vices/:viceID/activities[/:activityID]`, ...); anything else is `NotFound`. Only the vice forms (add or edit) open as
fullscreen dialogs; an entry's route opens its editor as the amount sheet (`ViceActivityEditorPage.route`, a
`ModalBottomSheetRoute`), so deep links and bead taps both reach it by name. On a user change `MyApp` pops every pushed route, since swapping `home` alone
leaves the old session's pages on the stack.

**Today and Trends.** `ViceTracker` is Today: one day as the Day Dial (`DayDial`, `lib/widgets/day_dial.dart`), a
24-hour face with a bead per entry at its local wall-clock time, a tally row per unarchived habit (`TallyRow`), and
the Log button (`LogButton`, `lib/widgets/log_fan.dart`). Dial geometry is pure functions in
`lib/data/dial_layout.dart`: angle from the wall-clock minute (a DST day's 15:00 sits at 15); bead radius
7.5·√(quantity ÷ typical) clamped to 5–14, typical being the habit's stored typical (Server side, `server.md`) or else the median
of its entries that day; a habit's later entries in one hour step out to the other tracks; neighbours on a track move
apart along the arc, never off it. Fan geometry is in `lib/data/fan_layout.dart` (up to eight wedges, then seven and
More). Face, hand and beads are `CustomPainter`s; each bead is also a `Semantics` button opening its entry's editor,
and a pointer tap goes to the nearest bead within 44 pt. Above 48 entries a day (`DialFace.mergeAbove`), each hour
with more than one becomes one `HourArc` on the first track, split by habit in proportion to entry count and labelled
with its count. `layoutBeads` holds arcs still and pushes the hour's lone beads clear (a bead wider than the gap
between two arcs overlaps both). Tapping an arc opens the entry nearest the tapped time; to a screen reader it is one
button naming the hour and each habit's total that opens the hour's latest entry, with one custom action per entry.
The dial is one `Semantics` node labelled `DayDial.summary` (day, each total, first and last entry times). Motion
follows `DialMotion`: a day change contracts the beads, then a hand sweeps round and each bead springs in as it
passes; a logged bead flies in from the `+` or wedge via `beadArrivalsProvider`; an edited one travels round the rim to its
new time, starting on the first frame the dial draws (the editor sheet leaves it ticking, so behind the sheet); a pending bead's dashed rim turns
until it syncs; under `MediaQuery.disableAnimations` all of it is a 150 ms fade and the clock ticks once a minute, so
widget tests of pending entries cannot `pumpAndSettle` with animations on. Day navigation is `DayPicker`
(`lib/widgets/day_picker.dart`): arrows, a sideways swipe on the dial, and the date pill's `CalendarSheet`; no oldest
day, no future one. Habits list oldest first everywhere, the order colours are given in, so Today reads
`viceListProvider` as well as the unarchived list and tests override both (`habitOverrides`, `test/fakes.dart`).

The Trends sheet (`TrendsSheet`, `lib/trends/`), a `DraggableScrollableSheet` over Today, replaced the Graph tab. Its
peek below the tallies is the chosen habit's sparkline; opened over the dial, it shows that habit over 7, 30 or 90
days or a year, by day or by week (counted back from today, range rounded down to whole weeks: `r4-weekly` B, so 30
days shows 28 and no week is short), a moving average (stepper up to 30 buckets, starting at 7 days or 4 weeks), the
range's total, average and peak, when in the day it happens, and an average week as a weekday-by-hour grid
(`weekdayHours`: each weekday averaged over how often it falls in the window). That arithmetic and the chart's axis
scale and label spacing are pure functions in `lib/data/usage_series.dart` and `lib/data/chart_scale.dart`. Chips list
habits in use oldest first, then archived ones marked "· archived", so the default is never archived. Compare, after
them, adds a row of chips to draw up to `TrendsSheet.maxCompared` (3) other habits over the chosen one: thin lines of
their totals under the same average, on one count axis whatever their units, named in the chart's summary, readout and
legend, kept in page storage with the habit. A priced habit adds a Count/Spend switch that charts its totals times
its price, axis and readouts in its currency, with no compared lines (their units and prices differ); a habit with a
strength adds Units (`TrendsView`; the chart takes a `TrendsScale`, money or strength), likewise without compared lines
or the line. On iOS a Health
chip, once on, watches `healthStateProvider` (never before, as it reads Health) and offers each Health measure with
values in the range and a numeric `metricCopy` (not mood); the one picked is a dashed line under the habit's, each
bucket the mean of its days (`bucketHealth`, `lib/data/trend_breakdowns.dart`; a gap where Health has none; sleep on
the day the night ended), scaled to its own low and high, named in the summary, readout and legend; only its id is
kept. What set it off (`TriggerBars`, `lib/trends/trigger_bars.dart`) splits each bucket's tagged entries by
top-level trigger area (`triggerShares`: an entry in several areas counts an equal part to each, free text as Own
words, past four areas the least merged into Other), sharing the chart's cursor, adjust and arrow keys. It reads the range through the graph query alone, one per habit drawn
(hour profile, week and stats come from the same entries), builds its panel only once out of the peek, and a tap on a day point opens that day's dial and read-only tallies in the sheet (`TrendsDay`). The chart is one
`Semantics` node labelled `TrendsChart.summary`, valued with the cursor's readout; arrow keys and a screen reader's
adjust move the cursor, Enter or activate opens its day. fl_chart paints titles outside the widget tree, so tests read
them from the chart's data. Today's list ends at the peek; the Log button rides the sheet's edge and shrinks away as
it opens.

From `ViceTracker.splitWidth` (900 pt) wide on any device (iPad on its side too), the same `ViceTracker` state lays
out a split view: Today's column (`ViceTracker.splitColumnWidth`), Log button at its foot, beside `TrendsSheet.pane`,
the panel always open with no peek or Close, whose day points move Today's dial via its day picker instead of opening
`TrendsDay` (and announce `TrendsSheet.shownOnDial`, since a screen reader's focus stays on the chart). Both forms
share one `PageStorage` entry: a resize across 900 pt keeps day and habit (the chart's cursor resets). Left and Right
step Today's day (`_stepDay`, from state, so presses within one frame each count) via a `CallbackShortcuts` around the
whole split view, or around Today alone under the sheet; the chart's own `Focus` takes them first. The Mac window
opens at 1200×780 (`r8-mac-window` B) to show the split view, minimum 390×600, frame saved as `MainWindow`
(`macos/Runner/MainFlutterWindow.swift`). On Quit the app delegate hides every window at once; Dart answers the exit request once every write
is acknowledged or after 3 s (`lib/writes/quit_when_synced.dart`), and the process exits half a second after that
rather than wait out Flutter's and Firebase's shutdown (it took seconds). Widget tests run at 800×600 (phone layout). The e2e suite follows whichever layout it gets
(`splitLayout`, `integration_test/support.dart`).

Reduce motion (Settings: Follow system / Reduce / Full, `reduceMotionProvider`) reaches widgets through
`ReduceMotionScope` (`MaterialApp.builder`, overriding `MediaQuery.disableAnimations`) and the framework through
`PenchantBinding` (`lib/design/motion_binding.dart`, made first in `main()`), whose `MotionOverride` resolves
`SemanticsBinding.disableAnimations`, which every default `AnimationController` (sheets, dialogs, implicit animations)
scales its duration by; the scope sets it on build.

Homepage has no tabs; its `PageStorage` bucket keeps Today's day and the Trends selection across rebuilds. Both read
the current day from `todayProvider`; Today follows it unless the user picked another day, and a log (always now)
returns a past day to today. Entry times go through `EntryTimeField` (`lib/widgets/time_dial.dart`) in the amount
sheet and the editor: a mini `TimeDial` (the day's other entries faded, a knob snapping to 5 minutes, clamped to now on
today; a slider to a screen reader, arrow and page keys) over an `EntryTimeController`, whose null time follows the clock
so an untouched new entry is logged at the moment of saving, to the second. The day under the dial opens the
`CalendarSheet` to move the entry to another day.
