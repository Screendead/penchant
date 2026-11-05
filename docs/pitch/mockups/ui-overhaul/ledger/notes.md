# Ledger: how it builds in Flutter

The mock-up is `index.html` (open it in a browser; every frame is live). Its tokens are in `tokens.json`. This note
maps each element to Flutter and lists what it costs and what it changes.

## Theme and tokens

- `ThemeData` for light and dark, with `themeMode: ThemeMode.system`, replacing the pink, dark-only seed. Its
  `ColorScheme` is filled by hand from `tokens.json`, not `fromSeed`. Everything outside the scheme (the five data
  colours and their inks and edges, `rule`, `ruleStrong`, `clear`, `clearInk`, `spoke`) goes in a
  `ThemeExtension<LedgerColors>`, so no widget hard-codes a colour.
- The neutrals are the icon's: light `bg` is its paper (#F6F4EF) and `text` its ink (#1D1C1A); dark mode swaps them
  (bg #141311, surface #1D1C1A). The app opens onto the icon's own paper, and the icon tile on the sign-in page takes
  a 1 px `ruleStrong` edge so it doesn't vanish into it.
- There is no accent hue. `ColorScheme.primary` is the text colour and `onPrimary` the background, so filled buttons
  are ink on paper (paper on ink in dark), text buttons are 600-weight ink, and the tab indicator, scrubber underline,
  focus ring, Undo countdown, save progress and sync circle are ink too. A data hue never doubles as chrome, so
  Alcohol's blue can't be mistaken for a button. The only non-data colours left are `error` and C5's `clear`.
- Elevation is 0 everywhere: `appBarTheme` (with `scrolledUnderElevation: 0`), `cardTheme`, `bottomSheetTheme`,
  `dialogTheme`, `navigationBarTheme`. Structure comes from 1 px `Divider`s and borders in `rule`.
- Fonts: Archivo Narrow, Atkinson Hyperlegible Next and Spline Sans Mono, all under the OFL. Bundle the TTFs as assets and
  set `GoogleFonts.config.allowRuntimeFetching = false`, or declare them in `pubspec.yaml` and drop google_fonts.
  Spline Sans Mono is set with `FontFeature.tabularFigures()`. It replaces Martian Mono, whose slashed zero made a
  muted 32 pt zero read as the null sign and gave the log a terminal feel; Spline's zero is plain and it is narrower.
  The mono is for numbers only: dates and words in the Trends readout, axis and stats are in the body face.
  Atkinson's own zero is slashed and has no alternate, so a digit inside copy ("30 days") still shows it.
- The `TextTheme` follows the `type.scale` table in `tokens.json`. Section labels are the only text set in capitals.

## Day (replaces the radar and the bars)

- The ledger is a `CustomScrollView`: a pinned header (`SliverPersistentHeader`) holding the title, the signature
  glyph, the gear and the scrubber, then a `SliverList` of `LedgerRow`s, then the log.
- Key: one line above the rows ("Today", "Last 7 days", "30-day high", each with a small ink swatch of the mark)
  replaces the old "Habit / Count" column heads, so the track explains itself without the figcaption. Each track ends
  in a 1 px tick, and the number after it is that habit's 30-day high.
- `LedgerRow`: a `Row` of the 3 px tab (`DecoratedBox`; hollow tiers use a 1 px `Border`), an `Expanded` column
  (name `Text` that wraps and is never cut, and the track), the count, and a 44 pt `IconButton`.
- Track: a `CustomPainter` (`TrackPainter`) for the rule, the seven tick marks, the bar, the cap and, on a clean
  day, the sage line. The bar's fraction animates through `TweenAnimationBuilder<double>` (180 ms,
  `Curves.easeOutQuart`). The ticks animate the same way.
- The amber edge in light mode (the amber bar is 2.8:1 on white) is a 1 px stroke in `dataEdge[0]` drawn under the
  bar. It applies to the bar, the cap, the sparkline and the average line.
- Rolling count: a `RollingDigits` widget. Each digit is a `ClipRect` around an `AnimatedSlide` of a 0 to 9 column
  (140 ms). The mono has tabular figures, so the widths never shift. Its `Semantics` label is the plain number.
- Signature glyph: a `CustomPainter` over the day's per-habit values (each normalised to that habit's 90-day high),
  in a `RepaintBoundary` and wrapped in `ExcludeSemantics`. A zero day draws the outline pentagon and the spokes, so
  the strip never shows a gap.
- Scrubber: a horizontal `ListView.builder(reverse: true, itemExtent: 46)`, which is lazy and goes back without
  limit. `ScrollController.animateTo` centres the picked day, and an `AnimatedPositioned` underline slides under it
  (180 ms).
- Day paging: a `PageView.builder(reverse: true)` with one page per day back, so a swipe pages. Rows enter with
  staggered `SlideTransition`s off one `AnimationController`, using an `Interval` for each row's 12 ms delay
  (240 ms in all).
- Clean day: an `AnimatedContainer` takes the row block to `clear` (260 ms). Each track's sage line is the painter's
  third animated value, with a 20 ms stagger. The copy keeps C5: "A clear day so far" / "Nothing recorded today."
- Log: a `SliverAnimatedList`. `insertItem` reveals a new line with a `ClipRect` and an `Align(widthFactor:)` going
  from 0 to 1 (220 ms, emphasized decelerate). Swiping left to delete is a `Dismissible(direction: endToStart)`
  that shows the Undo strip; tapping a line expands an inline editor (`AnimatedSize`).
- The rows' combined label ("Thursday 5 Nov: Coffee 3 drinks, ...") is one `Semantics` node on the list. It takes
  over from `ViceChart.summary`.
- A larger text scale only makes rows taller. The one thing to measure is the 32 pt count beside a long name at a
  text scale of 2 to 3. At that scale the count drops under the name (a `Wrap`), and a test pins that behaviour.

## Recording (no modal)

- '+' calls the decided "log one at the default quantity, now" action through `TrackerWrites.recordActivity`, with
  `settleWrite` as now. On a past day, '+' opens the row with that day preset, since logging "now" would land on
  another day.
- Tapping the row expands it in place with `AnimatedSize`, or a `SizeTransition` (220 ms):
  - a stepper (two 44 pt `IconButton`s around a `RollingDigits`);
  - the time chips "Now", "15 min ago", "1 h ago" and "Pick…", which are custom 4 px-radius toggle buttons;
  - for "Pick…", an inline `CupertinoDatePicker(mode: dateAndTime, use24hFormat: true, maximumDate: now)`.
- The live ticking clock and the lock toggle are gone. `ActivityDateField` stays for the editor, restyled.
- Saving shows a 2 px `LinearProgressIndicator` under the row, not a scrim.
- The 8-second Undo (C4) is an `UndoStrip`, a strip above the bottom bar that grows in with `AnimatedSize`.
  Its 1 px countdown is a `TweenAnimationBuilder` over 8 s. It replaces the SnackBar but keeps the same copy and
  timing.
- Sync: a pending line shows a hollow 6 px circle, which is `ViceActivity.pending` from the
  `includeMetadataChanges` listener. On acknowledgement it fills (an `AnimatedContainer`, 150 ms), then fades out
  after 1 s (`AnimatedOpacity`).
- Haptics: `HapticFeedback.selectionClick()` on taps and `HapticFeedback.lightImpact()` on a commit.
- Press and commit: '+' and the stepper buttons scale to 0.94 while held (90 ms, an `AnimatedScale` on the pointer
  state). On a commit the row takes a flash of its habit colour, 14% at 60 ms fading to nothing by 420 ms (a
  `ColoredBox` under the row's content driven by an `AnimationController`), so the eye lands on the row that changed.
  Both are skipped under reduced motion. That is the whole micro-motion budget: roll, extend, write, flash.

## Trends

- List: one row per habit with a 30-day sparkline, drawn by a small `CustomPainter`. Archived habits come last,
  marked "(archived)".
- Detail:
  - the habit chips;
  - a custom segmented control for 7 days, 30 days, 90 days and 1 year;
  - a stats row in mono (total, per day or week, busiest day or week). The totals are `RollingDigits`, and
    `UsageGraphView.summary` already computes them;
  - the chart;
  - Day/Week, and "Average of N days" with a stepper, which replaces the slider and its "buckets" jargon.
- Chart: a `CustomPainter`. fl_chart interpolates values but cannot trim a path, and the trace-in is the point.
  - Bars draw each bucket at 40% (45% in dark).
  - The average line is drawn in the habit's `dataInk`, not its `data` colour, so in light mode it separates from
    the 40% bars of the same hue (in dark the two are equal and the opacity does the separating).
  - The moving average is a monotone cubic `Path`. It traces in through `PathMetric.extractPath(0, length * t)`
    (480 ms, `Curves.easeInOutCubic`), 120 ms behind the bars' clip reveal.
  - The y ticks sit in an `AnimatedSwitcher` keyed by the scale, so they roll when the scale changes.
  - The crosshair is a `GestureDetector` (drag and tap) that feeds an index to the painter and to a mono readout.
  - The bucketing, moving average and axis maths stay in `lib/data/usage_series.dart` and
    `lib/data/chart_scale.dart`.
  - fl_chart can stay for nothing else, or be removed.

## Journal, Habits, history, settings

- Journal (a new tab): a paged list of the user's activities, newest first, with sticky day headers
  (`SliverMainAxisGroup` with a pinned header) carrying the day's glyph.
- Habits:
  - a `ReorderableListView` with drag handles. Colours do not move, because a habit's colour comes from its
    creation order;
  - "New" opens a `showModalBottomSheet` (10 px radius, elevation 0) with an underlined name field, a 0/60
    counter and the unit chips (the existing `Unit` enum);
  - archiving lives on the history page, with Undo.
- History: rows grouped by day, without the old "Quantity: 3" subtitle. The unit always agrees with the count.
  Swipe to delete gets Undo, which it lacks today. "Show older" pages by 50. Every state has an app bar with a back
  button: loading, not found, and sign-in required.
- Settings: plain ruled `ListTile`s. Account Settings drops the raw "Photo URL" field. Its actions show progress
  inline instead of swapping the whole body for a spinner.
- Tabs: a custom bottom bar (three `InkWell`s and an `AnimatedAlign` indicator, 250 ms) in place of
  `NavigationBar`. The tab switch is a horizontal `SharedAxisTransition` from the `animations` package (flutter.dev,
  a new dependency) in a `PageTransitionSwitcher`. Homepage already builds only the visible tab, and `PageStorage`
  keeps each tab's state.
- Pushes keep the platform route (`MaterialPageRoute` already slides on iOS). The sheet and the forms stop being
  fullscreen dialogs.
- Status strips (offline, refused writes, errors) keep their live regions (`Semantics(liveRegion: true)`). They grow
  with `AnimatedSize` (200 ms), and `RejectedWritesBanner` stays in `MaterialApp.builder`.
- Sign in: one `Form` with a "Sign in" / "Create account" text toggle (an `AnimatedPositioned` underline), the
  wordmark and icon, underlined inputs with left-aligned labels, the password rule as a live checklist, and errors
  as a tabbed strip instead of plain `Text`. One auth page replaces the M2 `BottomNavigationBar`.
- macOS (not mocked): a `NavigationRail` sidebar, with the ledger as a table beside a detail pane.

## Reduced motion

`MediaQuery.disableAnimations` makes every duration zero. The exceptions are day paging, pushes and the tab
switch, which become a 120 ms `FadeTransition`. Digit rolls become instant swaps, and traces draw at once. The
mock-up honours `prefers-reduced-motion` and has a "Motion: Reduced" switch to show it.

## What it changes beyond the UI

- It supersedes C2 (bars below 3 vices, the radar from 3): the radar leaves Today. That is Jack's call, and it
  overlaps `r2-today`.
- Each row's track needs the habit's last 30 days, so Day listens to a 30-day window instead of one day. The query
  has the same shape (`ownerID` plus a `createdAt` range), so the existing `(ownerID, createdAt DESC)` activities
  index covers it, but it reads about 30 times as many documents. The scrubber's glyphs extend that window as the
  user scrolls back.
- The Journal tab pages `ownerID == uid` ordered by `createdAt` descending, which is also the existing index.
  Read the Firebase docs and re-check it before building (CLAUDE.md).
- Manual habit order (dragging in Habits) needs a new optional `order` field on vices, which needs a rules change and
  a test. It is optional, so existing documents stay valid and sort by `createdAt` until they are moved.
- Units: every habit in the mock-up uses the existing `Unit` enum (drinks, items, times). Nothing here needs a new
  unit.
- Vocabulary: the UI says "habit" and the brand placeholder "Tracker". The data model keeps `vices`.

## Colour check

`validate_palette.js` (dataviz skill) on the direction's pinned palette:

The neutrals moved to the icon's paper and ink after this check; the hue checks don't depend on them, and
`tools/check-contrast.mjs` recomputes every text pairing from `tokens.json` (all pass AA in both themes; the tightest
is dark `dataInk[3]` at 4.50:1, and light amber is 2.52:1 on paper, so it keeps its edge).

- Light: the lightness band and chroma floor pass. CVD separation fails: blue and purple ΔE 5.0 (deutan). The
  normal-vision floor fails: red and orange ΔE 8.5. Amber contrast is 2.69:1.
- Dark: the lightness band fails (amber, orange and blue are too light), the normal-vision floor fails (red and
  orange ΔE 10.1), CVD separation warns (blue and purple ΔE 6.3), and contrast passes.

The hues are the icon's and the direction pins them, so they stay. Colour is never the only identity:

- every row, log line, Trends row and chip prints the habit's name;
- text in a habit's colour uses `dataInk`;
- light amber marks carry the 1 px edge;
- no chrome uses a data hue, so a colour on screen always means a habit.

The validator's rule for a palette in this band is to require secondary encoding, and the names are that encoding.

## Build cost (relative)

| Part | Size |
|---|---|
| Theme, tokens, bundled fonts, light mode | S |
| Day ledger: rows, track painter, rolling digits, glyph | M |
| Scrubber and day paging | M |
| Inline recording, time chips, picker, Undo strip, sync circle | M |
| Trends list and detail painter (trace, crosshair, stats) | M to L |
| Journal tab (new query, sticky days) | S to M |
| Habits reorder (plus the `order` field and rules) and history restyle | S to M |
| Auth, settings, status strips, empty and not-found states | S |
| Motion pass, reduced motion, haptics, end-to-end updates | M |

The e2e suite in `integration_test/` finds widgets by today's copy and widget types throughout (`find.text`,
`find.byType`), so it needs rewriting alongside.

## Tools

- `tools/render-stills.sh` regenerates the four stills (light, dark, and the states in both themes).
- `tools/check-motion.mjs` samples every animation mid-flight in real time (virtual time stalls CSS transitions).
- `tools/check-contrast.mjs` checks every text pairing in `tokens.json` against WCAG AA.
- `tools/check-narrow.mjs` loads the page at a 390 px viewport and reports any horizontal overflow.
