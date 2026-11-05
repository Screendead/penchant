# Petal: how each piece is built in Flutter

`index.html` is the clickable mock-up and `tokens.json` holds the tokens. `stills-*.png` are renders of
`index.html`; `./stills.sh` regenerates every one of them (`./stills.sh states` only those matching). Each is
`node shoot.mjs <out.png> "<query>" <w> <h> [waitMs] [js] [scale]` (headless Chrome over
CDP in real time, exiting non-zero on any page error; `--virtual-time-budget` proved unreliable for requestAnimationFrame and froze the springs
in one run). Query flags:
`theme=light|dark`, `rm=1` (reduced motion), `frames=today-busy,record,...`, `record=sheet|earlier`,
`probe=<bucket>`, `hist=1`, `signup=1`.

Every habit name in the mock-up is invented, and so is every number (seeded random data). Units come from the
existing `Unit` enum (drinks, times, minutes, items). Nothing reads Firestore.

## Theme and tokens

- `lib/theme.dart` defines two `ThemeData`s (light and dark) from `ColorScheme(...)` with explicit values, not
  `fromSeed`. `MaterialApp.themeMode` follows `ThemeMode.system`, and Settings > Appearance can override it.
- The tokens that `ColorScheme` has no slot for go in a `ThemeExtension<PetalColors>`: the five data fills, the
  five inks, spoke, clear, clearInk, danger, dangerInk and snackAction. `lerp` makes theme changes animate.
- A habit's colour is `PetalColors.habit(order)`: hue `order % 5`, and fill solid, hatched or dotted for
  `order ~/ 5`. `order` is its position in `createdAt` order across all vices, archived ones included, so
  `viceListProvider` already supplies it. Hatching and dots are an `ImageShader` built once per hue and theme,
  or a `CustomPainter` clip. With no new field, this needs no rules change.
- Type: `google_fonts` 8.2.1 with the TTFs bundled under `assets/google_fonts/` and
  `GoogleFonts.config.allowRuntimeFetching = false`. The `TextTheme` maps displayLarge to Gabarito 800, bodies
  to Figtree, and a `PetalText.numeric` style to Spline Sans Mono 500 for every number, time and tick.
- Shapes: `FilledButton`/`StadiumBorder` pills, `Card` with `elevation: 0` on `surface`, radius 20. The
  `InputDecorationTheme` is `filled: true`, its `focusedBorder` a 2 px accent `OutlineInputBorder` (radius 14),
  and labels sit above the field in a `Column`, so `floatingLabelBehavior` is never used.

## Today

- **Header**: a `CustomScrollView` whose first sliver holds the large day title in an `AnimatedSwitcher`
  (fade plus a 6 px `SlideTransition`, 220 ms). The avatar `IconButton` pushes Settings.
- **Day strip**: a `ListView.builder(scrollDirection: Axis.horizontal, reverse: true)`, so it reaches back without
  limit. Each item is a 46×74 `InkWell` whose glyph is a small `CustomPainter` (the same rose painter at 28 px). It
  needs each day's totals: one range query for the visible window, with the same shape as the day query (`ownerID` plus a
  `createdAt` range), so it needs no new index.
- **Rose**: a `CustomPainter` (`PetalRosePainter`). fl_chart has no polar-area chart, and its radar is what
  collapses to spokes. The painter draws:
  - one chord wedge per habit, with a 3 px gap built by offsetting each edge (the helper `wedgePts` in
    `index.html`) and rounded joins (`StrokeJoin.round`);
  - for a zero habit, a dotted outline in `muted` (`PathMetrics` dashes with round caps) over a 7% `muted` fill at
    the 30% floor. It is never in the habit's colour, so an empty slot cannot be read as a small value;
  - the reference rim as a dotted polygon, with spokes at 45% ink running 8 px past it;
  - for a pending entry, a 2 px dashed rim.
  Radius: `floor + (1 - floor) * sqrt(v / busiest30)`, where `busiest30` is that habit's own busiest day, so petals
  compare a habit with its own recent past, not with each other (the caption says "each habit's").
- **Rose animation**: each petal's radius is driven by its own `AnimationController.unbounded`, run with
  `animateWith(SpringSimulation(SpringDescription(mass: 1, stiffness: 380, damping: 26), from, to, 0))`.
  The mock-up's JS uses the same closed form, so the motion should match. Bloom and day morphs add a per-petal
  `Future.delayed` stagger (40 ms and 35 ms).
- **Labels**: anchored on each wedge's bisector at `R * cos(step / 2) + 14`, 14 px past the rim's edge (not its
  corners, which left the bottom label 40 px adrift), and cornered away from the centre. Real `Text` widgets in a
  `CustomMultiChildLayout` around the painter, so they follow the device
  text scale. A `TextPainter` measures them first; when they overflow, they switch to numbered markers plus a key
  list, never dropping an amount (this closes `r5-key-always`). Tapping a petal hit-tests the wedge angle in
  `GestureDetector.onTapUp` and sets a filter `StateProvider`.
- **Semantics**: the painter sits in the existing `Semantics(label: ViceChart.summary(...))` node, unchanged.
  C2 is kept: fewer than 3 habits draw horizontal pill bars in the same colours, an `AnimatedContainer` width on
  the same spring.
- **Busiest day in the last 30**: a new `busiest30ForUserProvider(uid)` over a 30-day `createdAt` range. It has
  the day query's shape, so it needs no new index; the cost is more reads (risk 2 in the pitch).
- **Log tiles**: a two-column `GridView` (shrink-wrapped) of 48 px tiles, radius 16, name left and count
  right-aligned in mono, so the counts line up as a column; a zero count is `muted`. Each is a `GestureDetector`:
  - `onTapDown` scales to 0.94 (90 ms); release springs back;
  - `onTap` writes through `trackerWrites.recordActivity` plus `settleWrite`, then
    `HapticFeedback.lightImpact()`;
  - `onLongPress` opens the sheet.
  The count is an odometer: one `AnimatedSlide` per digit column inside a `ClipRect`, 220 ms. Spline Sans Mono
  keeps every digit the same width.
- **Entries**: a `SliverAnimatedList`, so inserts and removals animate. Each row is a `Dismissible`
  (end-to-start) that deletes with the existing 8 s Undo snackbar. Pending rows show the existing
  `NotSyncedMarker` restyled.
- **Clean day**: the same painter with `cleanProgress` driving a path trim (`PathMetric.extractPath`, 500 ms),
  the sage wash (the rim polygon with a 16 px rounded stroke, not a circle) as an `AnimatedOpacity` (400 ms), and one `TweenSequence` breath (1.0 to 1.02 to 1.0, 1200 ms,
  `Curves.easeInOutSine`) run once from `initState`, never repeated. C5 stays quietly positive. The only how-to copy on Today lives here ("Tap a habit to log one;
  hold it for more."): a day with entries carries no instructions.
- **Offline banner**: `AnimatedSize` plus `SlideTransition` (240 ms, `easeOutCubic`), keeping its
  `Semantics(liveRegion: true)`.
- **Rejected write** (built: "Rejected write" on the busy frame): `RejectedWritesBanner` in `MaterialApp.builder`
  becomes a danger-tonal card pinned under the status bar over every screen, "Not saved" plus what was refused and
  when, and a tonal Dismiss pill; it enters on the spring from -24 px.

## Log sheet (record and edit)

- `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)`, with the shape at radius 28. The
  sheet's entrance uses a custom `AnimationStyle` with the spring curve.
- Habit picker: a horizontal `ListView` of `ChoiceChip`s styled as pills. It preselects the held chip or
  `lastUsedHabitProvider` (in memory, per session).
- Stepper: two circular `IconButton.filledTonal`s around the odometer. A `GestureDetector(onHorizontalDragUpdate)`
  scrubs by one step every 22 px, with `HapticFeedback.selectionClick()` on each step.
- Time: a `SegmentedButton<When>` (Now or Earlier). Earlier expands an `AnimatedSize` holding a
  `CupertinoDatePicker(mode: dateAndTime, use24hFormat: per locale, maximumDate: now)` with minute resolution:
  older days above, Today, then future days greyed and snapping back, as the iOS picker draws them. That replaces the
  lock toggle and the Material date and time pickers. `ActivityDateField` becomes this control.
- Save: a pill `FilledButton` whose child is an `AnimatedSwitcher` (label to `CircularProgressIndicator`) inside
  an `AnimatedContainer` that narrows to a circle. The 50% black scrim is removed. `settleWrite`, the 10 s timeout
  and the queued wording are unchanged; the sheet pops on settle, and the petal springs 160 ms later.
- Edit opens the same sheet pre-filled, with "Delete entry" as a destructive `TextButton`. The editor page goes.

## Trends

- A row of habit `ChoiceChip`s, with archived habits last as "Name (archived)". Then two `SegmentedButton`s
  (range 7/30/90/365; Day/Week), and "Average over N days" with − and + buttons where the slider and its
  "buckets" wording used to be. Changing the range resets N to a sensible default (3, 7, 14, 30).
- Chart: fl_chart 1.2 `LineChart` with `BarChart` behind it in a `Stack` sharing one scale from
  `chart_scale.dart`, or a single `CustomPainter` (simpler, and the hit-testing is ours):
  - raw buckets as neutral bars (`text` at 11% light, 16% dark); the touched bucket's bar takes the habit fill at
    100%. Habit-coloured bars at 35% read as brown in dark and fought the line;
  - above 120 buckets (365 by day) a bar is under 2.5 px, so the bars drop out and the area carries the shape;
  - the average as a curved 2.5 px line in the habit ink (`dataNInk` in light, since the fills are fill-only on
    paper), over a 12% area fill only when the bars are hidden.
  Draw-in is a path trim (500 ms, `easeInOutCubic`) with the area 100 ms behind.
- Readout: a fixed 44 px header row in the chart card (date, value in mono 22, unit, average), defaulting to the
  latest bucket and following `onPanUpdate`. A floating bubble covered the line where you were reading it.
- Stats row: three cards (total, daily or weekly average, busiest day or week) from the same numbers
  `UsageGraphView.summary` already computes. The summary's Semantics label is unchanged.

## Habits, history, settings

- Habits (Manage Data renamed): two `Card`s of `ListTile`s ("In use", then "Archived" last). Each row is a
  `Dismissible` that archives or restores, with an 8 s Undo through `trackerWrites.setViceArchived`. The swatch is
  a 22 px wedge `CustomPaint`. "New habit" opens the vice form as a sheet: name with a 60-character counter, and
  the unit as `ChoiceChip`s.
- History: a pushed page with a back button (no more dead ends without an app bar), a 30-bar sparkline
  (`AnimatedContainer` heights, staggered), entries grouped by day, `Dismissible` delete with Undo, and
  "Show older" paging at 50 as today.
- Settings: grouped `Card`s with Account, Export, Appearance (`SegmentedButton<ThemeMode>`), About (version in
  mono) and Sign out. The raw "Photo URL" field leaves Account Settings.

## Shell

- Phone: a `Scaffold(extendBody: true)` with a floating capsule tab bar (iOS 26's shape): a `Positioned` 236×62
  `ClipRRect` (radius 31) over a `BackdropFilter(ImageFilter.blur(20, 20))` at 74% paper, 16 px from the left and
  26 px from the bottom, holding three 76 px destinations over a `fill` thumb that slides on the spring
  (`AnimatedAlign`). A 140 px paper gradient, solid from 40%, keeps content out of the gap. The Log button is a
  separate `Positioned` 66 px circle on the same centre line: a `SweepGradient` ring in the five icon colours, a paper gap, an ink core, and the one
  ambient shadow. The drawer goes.
- Tab change: `PageTransitionSwitcher` with `FadeThroughTransition` from `animations` (a new dependency), 300 ms,
  with the incoming scale at 0.96.
- macOS: the same destinations in a `NavigationRail` sidebar, and the Log action as the rail's leading
  `FloatingActionButton`.
- Snackbars: `SnackBarBehavior.floating`, ink background, Undo in `snackAction`, and an 8 s countdown ring
  (`TweenAnimationBuilder` on a `CircularProgressIndicator` value). The C4 duration is unchanged.

## Auth

- One `Authenticate` screen: the icon `Image.asset`, the "Tracker" wordmark, and a `SegmentedButton` between
  Sign in and Create account, which replaces the M2 `BottomNavigationBar`.
- Create account expands an `AnimatedSize` with Confirm password and a live checklist of the existing
  password rule (8+ characters, upper case, lower case, a digit), each tick an `AnimatedScale`.
- Errors from `authErrorMessage` appear in a tonal danger card (`AnimatedSize`), not as plain `Text`.

## Reduce motion

When `MediaQuery.disableAnimations` is set:

- every spring becomes a 150 ms `AnimatedOpacity` crossfade;
- there is no bloom, stagger, breath or digit roll;
- haptics stay.

The mock-up honours `prefers-reduced-motion`, and its "Reduce motion" button simulates the setting.

## Accessibility notes measured or computed here

- Text contrast, computed from the tokens: `muted` is 5.1:1 on paper, 5.6 on surface, 4.6 on fill (light) and
  6.8 / 6.1 / 5.3 (dark); placeholders and the stepper hint now use `muted` at full opacity (at 80% they were 3.2
  and 3.7:1). `clearInk` on `clear` 5.5 / 9.8, `dangerInk` on `danger` 6.2 / 8.6, the snackbar action 9.6 / 4.9.
- Type is a whole-pixel ladder (11, 12, 13, 14, 15, 16, 17, 18, 22, 34, 40, 76); every tab root's title is 34.

- Light-mode data fills on paper measure 1.6 to 3.8:1, so they are fill-only. Coloured text uses `dataNInk`
  (4.9 to 6.6:1).
- The icon order puts coral and red next to each other. They are 10 OKLab units apart for normal vision, under
  the 15 floor; violet and blue are 6.3 apart under deuteranopia (the dataviz palette validator). The rose
  therefore always direct-labels name and amount, and separates wedges with a gap and a spoke, so colour is never
  the only cue.
- Spring check: stiffness 380 and damping 26 give a damping ratio of 0.67. That peaks at 216 ms with about 6%
  overshoot (the direction said about 4%) and stays within 0.5% of its target from 350 ms. The mock-up runs each
  spring for 450 ms.

## Not in the mock-up

- **9 or more habits**: in the direction, the rose shrinks to a summary and ranked habit rows become the main read.
  This is not built or demoed. The mock-up shows 5 habits, and 6 once you add one under Habits (striped colour).
- **Label overflow**: the fallback to numbered markers and a key list is specified above but not demoed.
- **The macOS rail**: described above but not drawn.

## What it costs

- **New code**:
  - the rose painter and its layout: the largest piece, about 2 to 3 days with tests;
  - the Log sheet, which replaces both the record dialog and the editor;
  - the bottom bar and Log button;
  - the theme extension and the font bundling.
- **Moderate rework**: Trends (a painter or the fl_chart stack), Habits and History (Dismissible plus Undo),
  Auth (one screen).
- **New dependency**: `animations`.
- **New query**: a 30-day window on Today, for the busiest day and the strip's glyphs.
- **Unchanged**: no data-model change, no rules change, no new index. `TrackerWrites`, `settleWrite`, the offline
  and rejected-write flows and both Semantics summaries stay as they are.
