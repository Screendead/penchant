Day Dial draws a day as a 24-hour dial. Every entry is a coloured bead at the time it happened, so a quiet day reads as a quiet clock and a busy one shows when it was busy. The chrome is ink on paper (paper on ink in dark). The five habit colours mean habits and nothing else.

## Content fundamentals

**Voice.** Write like a neutral, private, precise journal. State what happened and when, and never judge it. Use no streaks, goals, praise, warnings or "bad". Use no exclamation marks and no emoji. Keep sentences short and plain.

- Write in sentence case everywhere: buttons, titles, menu items ("Show older", "Export my data", "Forgot password?").
- Address the person as "you" only when it is about their journal or their device ("Your journal is private to your account.", "It will sync when you're back online."). The app never says "I" or "we".
- Name the habit, the amount and the time, in that order: "Logged **1 drink** of Alcohol at **21:10**". Undo copy repeats what it undoes: "Deleted **2 drinks** of Alcohol", then "Entry restored".
- Set every number in Mono and its unit in Text, singular or plural from the habit's unit: `2` *drinks*, `1` *time*, `80` *minutes*. Only the app's units exist: items, times, drinks, minutes. On a fan wedge "minutes" shortens to "min".
- Write times as 24-hour `hh:mm` ("08:10") and ranges with an en dash ("07:00–10:00"). Write dates as "Thu 5 Nov". Call the last two days "Today" and "Yesterday"; the date pill names an earlier day by its weekday with the date beside it ("Tuesday 3 Nov").
- Separate facts with a spaced middle dot: "drinks · 1,287 entries", "5 active · 1 archived", "Coffee · last 30 days". Group thousands with a comma.
- Copy for sync and refusal says where the entry is, not that something failed: "Saved on this device. It will sync when you're back online." / "Offline. New entries save on this device." / "1 change was not saved", then "Not saved: 2 drinks of Alcohol on Thu 5 Nov at 19:30. The habit was removed on another device."
- Empty states are calm facts: "A clear day so far" (today), "A clear day" over "nothing logged" (a past day), "Nothing in this range", "No average line".
- Hints say the gesture, then what it does: "**Tap** to log now · **hold** for amount and time", "Drag across the chart to read a day. Tap a day to open its dial.", "Swipe an entry left to delete it. Tap it to edit.", "Now · drag the hand to change the time".
- The wordmark and the sign-in title show the app's product name exactly as the app sets it today. This system does not choose the name. "Tracker" in the previews is a placeholder.
- Example habits in any mock-up, doc or test are made up. Use the set the previews use: Coffee, Takeaway, Alcohol, Late nights, Doomscrolling, and Sugar (archived).

## Visual foundations

### Colour: paper, ink and five habit colours

- Lay every screen on `bg`. Raise cards, sheets, the dial disc and controls on `surface`. Recess tiles, chips and tracks inside a surface with `surface2`.
- Set text in `text`, and secondary text (units, dates, captions, numerals, counts) in `muted`. Both meet 4.5:1 on `bg`, `surface` and `surface2` in both themes.
- Chrome is `accent`, with `onAccent` on its fills. That covers the primary button, the Log button, the now-hand, the scrub knob, selection, focus and today's ring. In light `accent` equals `text` (ink); in dark both are paper.
- **Habit colours are data only.** `data1` to `data5` fill beads, pips, fan wedges and chart series, and nothing else. Never use one for a control, a link, a selection, a focus ring or a status. Amber must never mean both "Coffee" and "press here". Red `data3` is a habit; errors use `danger`.
- **A habit's colour is its creation index**, counted in `createdAt` order with archived habits included, mod 5. Habits 1–5 are filled beads in `data1`–`data5`. Habits 6–10 are hollow rings (stroke 2.4) in the same hues, and 11–15 are dotted rings. The colour is computed on the device; nothing is stored. The source defines nothing past 15.
- Set text *about* a habit (its tally total, the Trends number, the average line) in its `dataNInk`, never in `dataN`. Each ink meets 4.5:1 on `bg`, `surface` and `surface2` in both themes.
- The only text on a habit colour is a fan wedge label, in `wedgeInk` (4.6:1 or better on all five).
- Bead treatment differs by theme. In light a bead is `dataN` with an inner 1.25px rim in `dataNRim`, which gives it 3:1 on the disc. In dark it is `dataN` with a 6px blur glow in `dataNGlow`. Each token is transparent in the theme that does not use it, so draw both every time.
- Links are `text`, weight 600, underlined (offset 3px, `muted` underline). Never a habit colour.
- Destructive actions are `danger` text, on `surface` or on a `dangerContainer` fill.
- A clear day uses `clear` (the wash) and `clearInk` (the ring and its copy). Elsewhere `clearInk` only ticks a met password rule.

### Type: one superfamily, three cuts

- **Red Hat Display** (`--font-display`) sets titles and the dial's numerals: `displayXL` for screen titles, `displayL` for sheet titles, `displayM` for the date pill's day word, `dialNumeral` for 00 06 12 18. The wordmark is Display 900 at 21px in the app bar and 42px on sign-in.
- **Red Hat Text** (`--font-text`) sets every word: `bodyL` for habit names, `body` for copy, `bodyS` for secondary lines and units, `label` for buttons, `labelS` for chips, segments and section labels.
- **Red Hat Mono** (`--font-mono`) sets numbers and nothing else, with tabular figures (`font-variant-numeric: tabular-nums`; `FontFeature.tabularFigures()` in Flutter). Use `monoXL` for the stepper amount, `monoL` for the hub clock and stat values, `monoM` for tallies and entry times, `monoS` for chart ticks, `dialTime` for bead times. Never set a changing number in a proportional face.
- Load all three from Google Fonts: Display 700 and 900, Text 400, 500 and 600, Mono 400 and 500. In Flutter, bundle them with `google_fonts` and runtime fetching off.

### Spacing and layout

- Build on the 4px steps `space-xxs` to `space-xxxl`. The screen gutter is `space-gutter` (20). Tallies and banner pills sit at `space-m` (16).
- Today, top to bottom on a 390pt phone:
  - the app bar (44pt: wordmark menu button left, SyncBadge right);
  - the day nav (a back circle, the date pill, a forward circle);
  - the dial at `size-dial`, centred;
  - the tallies, a scrolling list of `size-tallyRow` rows;
  - the Trends sheet peeking at 15% of the height, with the Log button docked on its top edge, centred.
- Pages (Habits, a habit's history, Settings) push over Today. Each has a 44pt bar with a back circle left and at most one circle action right, a `displayXL` title, an optional `bodyS` subtitle in `muted`, then cards separated by `labelS` section labels in `muted`.
- Sheets rise from the bottom with `radius-sheet` top corners, a 38×5 grab handle (`text` at 18%), 22px side padding and `space-xxl` below.
- On macOS from 900pt wide, split the window: the dial and tallies on the left, Trends on the right. No mock-up shows this yet.

### Shape and radii

- Controls are circles or pills. Circle buttons use `size-circleButton`, the Log button `size-logButton`. Buttons, chips, fields, segmented tracks, banners, the date pill and the UndoBar take `radius-pill` (or `radius-input`).
- Containers are softly rounded: `radius-card` (24) for cards and the menu, `radius-sheet` (32) for sheets, `radius-tile` (18) for stat tiles, `radius-iconTile` (22) for the app icon tile.
- No square corners anywhere in the app.

### Elevation and borders

- In light, a raised surface has a 1px `line` border plus `shadow-card` (cards, circle buttons, the date pill, the disc) or `shadow-sheet` (sheets). Floating things (the menu, banners, the fan hint) use `shadow-pop`. Thumbs and circles inside a `surface2` track use `shadow-tiny`.
- In dark, `shadow-card`, `shadow-sheet` and `shadow-tiny` are `none`. The 1px `line` border alone separates surfaces, and beads glow.
- The Log button uses `shadow-logButton`, a 6px `bg` halo that cuts it out of the Trends sheet's edge.
- Draw dividers inside cards as 1px `line`, inset to start after the leading pip or bead.

### States

- **Pressed:** scale to 0.92 (circles), 0.98 (wide buttons) or 0.88 (the tally +), springing back. No colour change.
- **Disabled:** 35% opacity, no pointer. A disabled primary button turns `surface2` with a `muted` label.
- **Focus:** a 2px solid `accent` outline at 2px offset on buttons. A text field turns its border `accent` and adds `shadow-focus`. Focus is always ink or paper, never a habit colour.
- **Selected:** the large segmented control slides an `accent` thumb with an `onAccent` label. The small one, inside a sheet, slides a `surface` thumb with `shadow-tiny`, and the label turns from `muted` to `text`. A habit chip fills with its `dataN` at 18% over `surface` and takes a 1.5px border in its `dataNInk`.
- **Zero:** a tally at 0 sets its name and number in `muted` and its pip at 40%.
- **Pending (not yet synced):** a hollow bead with a dashed rim (`dataN`, dashes 3.2/2.6) that turns once every 2 s. When the server acknowledges it, the fill scales up from the centre over 240 ms. Rows add "Not yet synced" with the cloud-up icon in `muted`.
- **Archived:** a habit keeps its colour. Its chip adds "· archived" in `muted`, and it is listed last under an "Archived" section label.
- **Error:** `dangerContainer` pills with a `danger` icon and `text` copy. The pill drops in on a spring. Never red text alone.

### Accessibility: what falls short, and the fix

Every text pair meets 4.5:1 in both themes, and `accent` marks meet 3:1 everywhere. These marks fall short. Each fix below is proposed and not yet made.

| Where | Light | Dark | Rule and fix |
|---|---|---|---|
| `data1`, `data2`, `data5` fills on `surface` / `bg` | 1.8, 2.6, 3.0 / 1.6, 2.7 | 4.1 or better | Beads carry `dataNRim` (4.4:1 or better on `surface`). A pip is always beside its habit's name, so its colour is never the only cue. |
| Ring beads (habits 6–10) | as above | passes | The mock draws them without a rim. Proposed: in light, add a 1px outer stroke in `dataNRim`. |
| Chart raw line and day dots in `dataN` | as above | passes | The average line is `dataNInk`, and the readout pill states each value. The raw series is context, not the only carrier. |
| Selected chip border | `data1` was 1.5 on `surface2` | passes | Fixed here: the border takes `dataNInk` (5.0:1 or better), not the mock's `dataN`. |
| `line` hairlines | 1.2 | 1.4 | Decorative. A text field is a `surface` pill with a `line` border on `bg`, so its edge is under 3:1. Its leading icon and placeholder identify it. Proposed if an audit asks: a `muted` field border at rest. |
| Small segmented thumb (`surface` on `surface2`) | 1.2 | 1.1 | The selected label also turns `muted` to `text`. Proposed: give the thumb a 1px `line` border plus `shadow-tiny`, or use the `accent` thumb. |
| `spoke` on `surface` | 2.9 | 4.7 | A grid. The numerals (`muted`, 5.9:1) and the hub carry the time. |

### Motion: orbital, 150–700 ms

Motion follows the dial: things travel along arcs, sweep clockwise and land on a spring. Curves are `easeInOutCubic` for travel, `easeInCubic` for exits and `easeOutCubic` for entrances. "Spring" means mass 1, stiffness 220, damping 22, carrying release velocity where there is a drag.

| Moment | Curve | Duration |
|---|---|---|
| A bead travels from the Log button or a wedge to its hour, along a quadratic arc, growing from 11 to its radius | easeInOutCubic | 520 ms |
| Landing: the bead overshoots to 1.25 and springs to 1; a ring ripples out 16px and fades; light haptic | spring + easeOut ripple | 300 ms ripple |
| A tally number rolls up (or down) to its new value | cubic-bezier(.2,.8,.2,1) | 300 ms |
| Day change: beads contract to the hub | easeInCubic | 200 ms |
| Then a hand sweeps a full turn, and each bead springs in as the hand passes it | easeInOutCubic | 600 ms |
| Clear day: spokes fade to 25%, the `clearInk` ring draws on clockwise | easeInOutCubic | 600 ms |
| The Trends sheet snaps to peek or open | spring with release velocity | |
| The chart morphs between ranges (both series resampled to a fixed count) | easeInOutCubic | 450 ms |
| A chart day opens its dial (container transform from the point) | easeInOutCubic | 450 ms |
| Pages push and pop (fade-through, from 0.94 scale) | cubic-bezier(.2,0,0,1) | 320 ms |
| The fan opens: wedges spring out of the Log button 30 ms apart; the + turns 45° to × | spring, 30 ms stagger | close 160 ms |
| Hold on a wedge opens the amount sheet; medium haptic | | 400 ms hold |
| The time scrub snaps to 5 minutes; selection haptic per step | | |
| A pending bead's dashed rim turns; on sync the fill grows | linear / easeOutCubic | 2 s a turn / 240 ms |
| Banner pills drop from the top | spring | about 260 ms |
| The UndoBar's countdown ring empties | linear | 8000 ms |

**Reduce motion** (`MediaQuery.disableAnimationsOf`): no travel, sweep or spring. Beads and content fade in together over 150 ms, and the now-hand moves once a minute without animating.

## Iconography

- Icons are single-stroke line glyphs on a 24×24 grid: 2px stroke, round caps and joins, no fill. They are drawn in `text`, or in `muted` for chevrons, menu icons and field icons. Size them at 20px in circle buttons and menus, 16px in the tally + and stepper, 18px in banners and fields, and 28px in the Log button.
- Use the set in `assets/Icons/`, copied from the mock-up: left, right, down, plus, minus, x, cloudok, cloudoff, cloudup, grid, gear, trash, pencil, eye, mail, lock, check, alert, sync, shield, user, share, info. Each file is drawn in light-theme ink (`#1d1c1a`). Inline the path and set `stroke` to the token you need. An `<img>` cannot recolour it.
- The SyncBadge's cloud glyphs say the state: cloudok synced, cloudoff offline, cloudup not yet synced.
- No emoji, no filled icons and no icon-only habit marks. A habit is shown by its pip or bead and its name, never a pictogram.
- The app icon (the five-wedge pentagon in the mock-up) belongs to the open brand call and is not an asset of this system.

## The Day Dial

The dial is the system's one chart. Draw it exactly as below.

- **Frame.** Use a square of `size-dial` with viewBox `-160 -160 320 320`. Time runs clockwise from 00 at the top, with 06 right, 12 bottom and 18 left. Angle = minutes since local midnight ÷ 1440 × 360°.
- **Disc.** A circle of radius 124 in `surface` with a 1px `line` rim and `shadow-card` in light. Inside a sheet, the disc is `surface2` and the hub `surface`.
- **Spokes.** Draw 24 spokes in `spoke`. The eight majors (every 3 hours) run from radius 54 to 140 at 1.4px, at full strength. The minors run from 64 to 132 at 1px and 45% opacity. Round the caps.
- **Numerals.** 00, 06, 12 and 18 sit at radius 152 in `dialNumeral`, `muted`.
- **Hub.** A circle of radius 44 in `bg`. Today shows the clock in `monoL` (21px) in `text` above "15 entries" in `bodyS` `muted`. A past day shows the weekday ("Tue") in place of the clock.
- **Now-hand (today only).** A 2px `accent` line from the centre to radius 140, a 3.2 centre dot, and a ringed tip (radius 3.6, `surface` fill, 2px `accent` stroke) on the rim at 124. Behind it, an elapsed arc on the rim from 00 to now, 2px `accent` at 22%. The hand ticks every second, or once a minute under reduce motion.
- **Beads.** One bead per entry, at its `createdAt` time, coloured by its habit (see Colour).
  - Radius = 7.5 × √(quantity ÷ the habit's typical quantity), clamped to 5–14. Size is relative to each habit's own typical entry, and the UI explains it in one line.
  - The first entry of a habit in an hour sits on the track at radius 100. Later ones in the same hour step out and in to 116, 84 and 68, then repeat.
  - Neighbours on a track push apart along the arc until their edges are 1.5 apart.
  - Every bead has a hit target 6 larger than its radius and opens its entry sheet.
- **Times on sparse days.** On a day of 4 entries or fewer, each bead carries its time in `dialTime` `muted`, on the hub side, haloed 4px in `surface`. Above 4 entries the tallies and a tap carry the times.
- **Dense days.** Above roughly 48 entries, merge an hour's beads into one arc labelled with its count.
- **Clear day.** With no entries, dim the spokes to 25% and lay a 16px `clear` band at radius 116. Draw a 2px `clearInk` ring at 60% on it, clockwise from 00. The hub reads "A clear day" over "so far" (today) or "nothing logged" (a past day) in `clearInk`, Text 600 at 12.5px.
- **Mini dial** (amount sheet). The same face at 216px with the day's other beads at 40%. Add a scrub knob (radius 11, `accent`, 3px `surface` stroke) on radius 112, and an `accent` 3px hand from 42% to 90% of that radius. The hub shows the chosen time. Today clamps the knob to now.
- **Hour ring** ("When it happens"). A 100-unit dial: `surface` disc, a `line` circle at 26, four `spoke` ticks. Each hour's total is a wedge from 26 out to 46 at the busiest hour, in the habit's `dataN`. "24 h" sits at the centre.
- **Semantics.** The dial is one labelled node: "Today, Thu 5 Nov. Coffee 5 drinks, Takeaway 5 items, Alcohol 4 drinks, Late nights 1 time, Doomscrolling 80 minutes. First entry 00:40, last 20:50." A clear day ends "Nothing recorded." Each bead is its own button that opens its entry. The tallies' + buttons are the list path for VoiceOver and Switch Control.
- **Do not** draw a radar, bars or a pie for a day, and never show a habit colour on chrome. Never move a bead off its time to tidy the layout; push it along the arc only.

## Components

- **Today:** DayDial (with Bead and ClearDay), DayPicker (the day nav and calendar), TallyRow.
- **Recording:** LogButton (with its fan), AmountSheet, EntrySheet, UndoBar.
- **Trends:** TrendsSheet (peek and header), TrendChart (stats, chart, readout, average stepper), HourRing.
- **Controls:** Button, Chip, SegmentedControl, TextField.
- **Status:** SyncBadge, Banner.
- **Pages:** ListCard (habit, entry and settings rows), Menu.

Each card's README says what it takes and when to use it.
