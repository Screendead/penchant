# Day Dial: how it is built in Flutter

`index.html` is the mock-up (open it in a browser; every phone is live). `tokens.json` holds the tokens. The stills
are `stills-light.png`, `stills-dark.png` and `stills-record.png`. `shoot.mjs` re-renders them with headless Chrome
over the DevTools protocol (`node shoot.mjs out.png 1400x2950 "theme=dark&state=fan" 3000`). Chrome's own
`--screenshot` with `--virtual-time-budget` barely advances `requestAnimationFrame`, so it catches animations half
done. Habit names and entries are made up.

## Theme and tokens

- `ThemeData` for light and dark built from `tokens.json`, with `themeMode: ThemeMode.system`. That replaces the
  dark-only pink seed. A `ThemeExtension<DialColors>` carries what `ColorScheme` has no slot for: the `data1-5` and
  `data1-5Ink` pairs, `spoke`, `clear` and `clearInk`, and the bead treatment (rim in light, glow in dark).
- The colour of a habit is its creation index (`createdAt` order, archived habits included) mod 5. Index 5-9 draws
  a ring and 10-14 a dotted ring. This is computed on the device and adds no stored field.
- Fonts: `google_fonts` 8.2.1 (Red Hat Display, Text and Mono), with the `.ttf` files bundled and
  `GoogleFonts.config.allowRuntimeFetching = false`. Mono numbers use `FontFeature.tabularFigures()`.
- The hard-coded colours go: the pink focus border, the green ticks and seed, and the black scrims become tokens.

## Today: the dial

- **The dial** is a `CustomPainter` behind a `RepaintBoundary`. It paints the disc, the 24 spokes, the numerals, the
  elapsed arc and the now-hand. Each bead is its own small painter in a `Stack` positioned from the layout function
  (angle = `createdAt` minutes / 1440, size = `sqrt(q / typical)`, the same hour's beads stacking outward, neighbours
  pushed apart along the arc), so each bead can animate on its own. Above roughly 48 entries in a day, an hour's
  beads merge into one arc labelled with its count.
- **Beads are hit-tested** in the painter's `hitTest`, and each one is a `Semantics` node with
  `onTap` that opens its entry sheet.
- **The now-hand** uses a `Ticker` that repaints once a second (once a minute under reduce motion). Midnight moves the
  day on through `todayProvider`, as now.
- **Tallies** are a `ListView` of rows in fixed habit order. The total is an `AnimatedSwitcher` with a vertical
  `SlideTransition`, which gives the roll. Each row's `+` logs the default amount: that is the list path for VoiceOver
  and Switch Control.
- **Semantics:** the dial keeps one `Semantics` label, `DayDial.summary`, which gives the totals and the first and
  last entry times (shown under frames 1 and 2). The fan segments are `CustomSemanticsAction`s on the Log button.
- **Day change:** a `GestureDetector` takes horizontal drags on the dial, and the `‹ ›` circles call the same method.
  One `AnimationController` runs the contract (200 ms, `easeInCubic`). A second runs the sweep (600 ms,
  `easeInOutCubic`), and each bead starts a `SpringSimulation` (mass 1, stiffness 220, damping 22) as the hand passes
  it.
- **Clear day:** the spokes fade to 25% and the sage ring draws on with a `TweenAnimationBuilder` (600 ms). The hub
  copy is C5's "A clear day so far".
- **Calendar:** a `showModalBottomSheet` holding a month grid. The dots come from one month-range query per month
  shown, which goes back without limit and needs no new index: it is the existing `ownerID` + `createdAt` shape.

## Record

- **Log button:** a 64 pt `FloatingActionButton`-sized circle docked on the Trends sheet's edge.
- **Fan:** an `OverlayEntry` holding a `BackdropFilter` blur and a `CustomPaint` of pentagon wedges, laid out like the
  icon, with at most 8 per ring and "More" beyond. Each wedge springs in, 30 ms apart. `Listener` and `onLongPress`
  separate a tap (log the default amount now), a 400 ms hold (the amount sheet) and press-drag-release from the Log
  button (hit-test on pointer up).
- **Bead travel:** a `Path` (quadratic Bézier) followed with `PathMetric.getTangentForOffset` under an
  `AnimationController` (520 ms, `easeInOutCubic`), drawn in the overlay. On landing the bead springs, a ripple ring
  fades over 300 ms and `HapticFeedback.lightImpact()` fires (HTML cannot vibrate, so the mock-up has no haptic). The
  SnackBar keeps C4's 8 s Undo and shows a countdown ring (`TweenAnimationBuilder` over a `CircularProgressIndicator`).
- **Amount sheet:** a `showModalBottomSheet` with a stepper and a mini dial whose knob is dragged through a
  `GestureDetector` on the angle, snapping to 5 min with a `HapticFeedback.selectionClick()` per step, and clamped to
  now on today. It replaces the lock toggle, the seconds ticker and the Material date and time pickers. Editing an
  entry reuses the same sheet, and the bead travels round the rim to its new time.

## Trends

- **The sheet** is a `DraggableScrollableSheet` with `snap: true` and `snapSizes: [0.15, 0.92]`. The 15% peek
  shows a sparkline.
- **The chart** is fl_chart `LineChart`: the raw series at 50%, the moving average as a curved 3 px line with a 10%
  area below it. `LineTouchData` draws the cursor and the readout pill.
- **Morphing between ranges:** fl_chart tweens spot by spot, so resample both series to a fixed count (the mock-up
  uses 221) before handing them over, and the line morphs cleanly. That keeps the existing pure functions in
  `usage_series.dart` and `chart_scale.dart`, and the animation is `duration: 450ms, curve: easeInOutCubic`.
- **Controls:** the habit chips are `ChoiceChip`s, the range and Day/Week are `SegmentedButton`s restyled as pills,
  and "Average over N days" is a stepper. That replaces three dropdowns and the "buckets" slider.
- **Stats row and "When it happens":** pure functions next to `UsageGraphView.summary`, which already computes
  total, average and peak.
- **Tapping a day point** opens its dial through `OpenContainer` from the `animations` package (a new dependency,
  450 ms).

## Pages, banners and state

- **Habits, history and settings** are pushed with `SharedAxisTransition`/`FadeThroughTransition` (`animations`,
  320 ms). Every page has an app bar with a back circle, which fixes the dead-end loading and not-found states.
- **History:** a grouped `ListView` whose entry rows are `Dismissible` (end to start) with Undo. That adds the undo
  delete has lacked.
- **Pending entries:** a hollow bead whose dashed rim rotates (a `RotationTransition`, 2 s a turn). When
  `hasPendingWrites` clears, the fill scales up from the centre over 240 ms.
- **Offline and refused writes:** pills that drop from the top on a spring, using `SlideTransition` with a
  `SpringSimulation`-driven controller and keeping their `liveRegion` semantics. The refused pill expands into its
  list with `AnimatedSize`. They replace `OfflineBanner` and `RejectedWritesBanner` and keep the same data.
- **Auth:** one screen. The segmented control replaces the M2 `BottomNavigationBar`, the password rule becomes an
  animated checklist, and errors are a styled pill instead of plain `Text`.
- **Reduce motion:** check `MediaQuery.disableAnimationsOf(context)` everywhere. When it is on there is no travel,
  sweep or spring: things fade over 150 ms, and the hand moves once a minute.
- **macOS:** a split view, with the dial and tallies on the left and Trends on the right (`LayoutBuilder` from
  900 pt up). The mock-up does not show it.

## What it changes beyond the UI, and what it needs from Jack

- **It supersedes C2 (bars below 3 vices) and the radar, and needs Jack's call.** It overlaps `r2-today` and retires
  `r5-key-always`, because amounts always sit in the tallies.
- **Units:** the mock-up uses only the existing enum (items, times, drinks, minutes). Units such as cups, meals or
  sessions would be a data-model change (`r2-data-model`).
- **The zone problem gets more visible:** entries sit at their local time, so they move round the dial when the
  device's time zone changes (CLAUDE.md, Days).
- **Bead size needs a one-line explainer:** it is relative to each habit's typical entry.
- **Optional "your usual" ghost beads** (the last 7 days at their times) cost one 7-day query, which the current
  index already covers. They are left out of the mock-up.
- **Rough build size:** about 2 weeks for the dial, the fan and bead travel, the Trends sheet and the restyle. The
  dial painter and the fan gesture handling carry most of the risk. The new dependency is `animations`.
