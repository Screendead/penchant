# Handover — Tracker

*Updated 2026-11-06. Audience: the next agent, or Jack. This file holds the current task: the queue, where each item
stands, the calls waiting on Jack, and the options set aside. Update it in the same commit that closes an item or
records a call. Git holds the history. How the code works lives in `CLAUDE.md`.*

## The goal

A production-quality habit journal for Jack's own use (`r2-privacy`, Jack, 2026-11-06): "I'm not actually going to
put it on the App Store; it's just for me." Build it with release polish, but leave the store, legal and payment work
(privacy policy details, App Store listing, Pro and billing, TestFlight) undone until and unless he decides to sell
it. No paid Apple Developer account for now (Jack, 2026-11-06), so App Attest, TestFlight, the App Store and Sign in
with Apple wait; the domain waits until a release. The order stays: make what exists work, keep it safe to change,
burn down the debt, then build the journal and insights from `ideas/`.

## "Do the next thing"

Take the **top unblocked item in the queue below**, do it end to end (branch, PR, end-to-end run, merge), tick it
off here in the same PR, and stop. If it is blocked on Jack, skip to the next one and say so. `/finish-and-pitch`
works through the whole queue: its DECIDED list is the queue, its UNDECIDED list is "Calls waiting on Jack".

## Where things stand

| Item | State | Where |
|---|---|---|
| Standing rules, CI checks, emulator and iOS e2e harness | Merged 2026-11-02 (#24, #25, #29) | `CLAUDE.md`, `.github/workflows/`, `tools/e2e.sh` |
| Firestore rules rewrite (#27) | Deployed to production by Jack 2026-11-03 | `firestore.rules` |
| Recovered features and the fixes for Jack's two reported bugs (#28) | Merged and live 2026-11-03 | `lib/` |
| Jack's round-1 calls C1–C19 | Picked 2026-11-03; built in wave 3 | below |
| Wave 3: Today and recording C2–C5 (#36), rules details C12–C14 (#33), platform and repo cleanup C1 C6–C11 (#34), ideas rework C15–C19 (#35) | Merged 2026-11-03. The rules from #33 reached production through CI on 2026-11-04 (below) | `lib/`, `firestore.rules`, `.github/workflows/deploy-firestore.yml`, `ideas/` |
| Wave A of the finish-and-pitch run: Dependabot #37 #38, seed script emulator-only (#44), parsers default every field (#45), shared write layer `TrackerWrites` (#46), versioning 0.1.0 + changelog + release workflow (#43) | Merged 2026-11-03 | `lib/`, `admin/`, `CHANGELOG.md`, `.github/workflows/release.yml` |
| Security patch: cloud_firestore 6.10.2, Firebase iOS SDK 12.19.3, for Firebase's eMudhra CA notice (#56) | Merged 2026-11-03; Jack's iPhone runs release 0.1.0 (244) built from it | `pubspec.yaml`, `ios/Podfile.lock` |
| Wave B: rules-test deps (#49), accessibility (#51), navigation (#52), offline logging (#53), backend hardening with App Check client wiring (#55), account export, deletion, password reset and verification behind `accountProvider` (#54); register additions (#57); round-3 calls on the pitch page (#58) | Merged 2026-11-03/04. The new activities index is deployed to production (by Claude, with Jack's leave, 2026-11-03). App Check is wired but not registered or enforced (Jack's list) | `lib/`, `integration_test/`, `firestore.indexes.json` |
| Wave C: register additions refreshed (#60), refused offline writes surface in a banner and Manage Data counts offline (#61), startup and load errors show a message with Retry (#62), dead lint and codegen tooling removed with riverpod_lint running in CI through `dart analyze` (#63), the record dialog's vice dropdown keyed on the id (#65, an e2e flake) | Merged 2026-11-04 | `lib/`, `.github/workflows/checks.yml` |
| Wave D: data layer (#68), repo hygiene (#70), usage graph (#69), locale formatting (#67), widget state (#71), dead code and a `dart format` CI step (#66), Today chart keeps vice names readable at large text (#74), admin glob override for Dependabot alerts 197/198 (#75), pitch round 4 (#73) | Merged 2026-11-04. Each ran the full iOS e2e (31 tests) before merge, except #73 (docs) and #75 (seed script only; ran it under the emulators) | `lib/`, `admin/`, `docs/pitch/` |
| CI deploys rules and indexes | On since 2026-11-04: Jack set `DEPLOY_FIRESTORE_RULES=true` and granted the roles. Run 41822697732 deployed ("Deploy complete!"), and #71's merge deployed too. The 4 unlisted production indexes stay (no `--force`) | `.github/workflows/deploy-firestore.yml` |
| Web site | Down: returns 404 (checked 2026-11-04) | |
| macOS target (#47) | Merged 2026-11-05: `E2E_DEVICE=macos tools/e2e.sh` passes 31/31 (15 files, one `flutter test` each) beside iOS 31/31 | `macos/`, `.github/workflows/macos-build.yml` |
| UI overhaul: Day Dial (`r6-ui-direction`, Jack 2026-11-05) | Step 1a, the theme foundation, merged in #79: tokens, light and dark themes following the system, bundled Red Hat fonts, habit colours by creation order. Step 1b, Today, in review in #83 (`feat/today-day-dial`): the dial, tallies with one-tap log, the Log fan, day picker and calendar; the radar and bars are gone | `lib/design/`, `assets/fonts/`, `lib/widgets/day_dial.dart` |
| Rounds 2, 3, 4 and 8 on the pitch page | All picked by Jack 2026-11-06 and recorded below; round 5 is moot (the radar left Today in #83). Three calls from 1d/1e are not on the page yet (Calls waiting on Jack) | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Brand: Penchant (`r2-brand`) and "habit" wording | Applied to the app's strings in #81 (2026-11-05). Bundle ID `com.screendead.penchant` on iOS and macOS with the new Firebase config, shared by the Mac (`r2-mac-config`), merged in #84 (2026-11-06); both development profiles exist, and a signed `flutter build ios --release` carries the new ID | `lib/firebase_options.dart`, `ios/`, `macos/` |
| Tech-debt register | 21 issues: 0 critical, 0 high, 10 medium, 11 low (`tools/tech-debt-recount.py` on `feat/bundle-id-penchant`, 2026-11-05; from 162 on 2026-08-11) | `tech-debt/README.md` |
| Product backlog | 28 ideas for the journal positioning (versioning, offline-first, account deletion and export shipped), roadmap in its README | `ideas/README.md` |

Baseline: wave D's PRs each ran `tools/e2e.sh` 31/31 on iOS before merging (2026-11-04); CI runs `dart analyze`, the
`dart format` check, `flutter test` and the rules tests. `flutter build macos` fails on master (deployment target);
#47 fixes it. Test counts were last measured before wave D: re-measure; don't trust this.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's calls below. Work it top down; skip what is blocked
and say so. Items under one number can run in parallel in separate worktrees; only one agent at a time runs
`tools/e2e.sh` or uses the default emulator ports. Subagents write PR bodies to uniquely named scratchpad files: the
scratchpad is shared, and a generic `pr-body.md` once put one PR's description on another.

1. **The Day Dial UI overhaul** (`r6-ui-direction`, below). The source of truth is branch
   `origin/design/ui-overhaul-day-dial`, folder `docs/pitch/mockups/ui-overhaul/day-dial/`: `index.html` (the live
   mock-up), `tokens.json` (mirrored in `lib/design/tokens.json`), `notes.md` (how each part is built in Flutter) and
   the stills. One PR per step, in order; every screen keeps working between steps, and each PR keeps
   `tools/e2e.sh` green by updating the tests its screens break. Habit names in examples are made up; the product
   name is Penchant (`r2-brand`; the mock-up's "Tracker" is a placeholder).
   - **a. Theme foundation:** tokens, light and dark `ThemeData` with `themeMode: system`, bundled fonts, the habit
     colour function, the hard-coded colours replaced. In review (#79).
   - **b. Today:** the dial (`CustomPainter`, beads at their times, now-hand, clear-day ring), the tally rows with a
     `+` each, the one-tap "log one" action (the default quantity, now, with C4's 8-second Undo; this was the
     layout-neutral half of one-tap logging), the Log button and its fan, the amount sheet that replaces the record
     dialog for new entries, and the calendar sheet. The radar and C2's bars leave Today. In review in #83,
     all of it but the amount sheet: a held wedge (or More, past eight habits) opens the
     existing record dialog with the habit chosen, so new entries with an amount or time still go through it. Left
     for later steps: the amount sheet (with 1d's editor, which reuses it), the SyncBadge pill (it needs a signal for
     "everything synced" the app does not have; the offline banner and the day's pending note stay), merging a dense
     hour's beads into one arc above about 48 entries, and docking the Log button on the Trends sheet (1c). Bead
     size is against the habit's median entry on the shown day, so it costs no extra read; the "your usual" ghost
     beads and a cross-day typical would cost a 7-day query. `r5-*` (the radar's key) are moot once this merges.
     Fidelity pass in review in #94 (`feat/today-fidelity`), after Jack found Today unlike the mock-up: the
     Penchant wordmark menu (Habits, Settings, sync footer) replaces the drawer, the Synced pill is built on
     `waitForPendingWrites` (`syncStatusProvider`), the mock-up's spacing fits five tallies above the Log button on a
     390 x 844 phone, light shadows, stroke icons, dimmed zero pips. Side by side in
     `docs/pitch/mockups/ui-overhaul/day-dial/fidelity/`; re-render with `tools/fidelity/`. Still different, by
     the 3:1 floor: the clear day's major spokes, pip and wedge rims, the sparkline's daily line; Jack's round 8: no coach pill, the
     clear day's majors at 25%, and bead size against a stored typical (`r8-bead-size`, open on how it is computed).
   - **c. Trends sheet:** a `DraggableScrollableSheet` over Today that replaces the Graph tab: habit chips, range and
     Day/Week segments, the average stepper, stats, "when it happens", and a day point opening its dial. In review in #89
     (`feat/trends-sheet`, stacked on #83): all of it, and the Log button docks on the sheet's edge. Left for 1f: the
     chart's morph between ranges (fl_chart tweens only equal-length series, so a range change snaps) and the day's
     container transform with the `animations` package (it fades in place). The weekly remainder changes:
     `r4-weekly` is B, round the range down to whole weeks (item 4). The average now runs to 30 buckets, starting at 7 days or 4 weeks, as the mock-up has it.
   - **d. Habits, history and the entry editor:** Manage Data becomes Habits, the history list gets swipe-to-delete
     with Undo, and editing reuses the amount sheet. In review (`feat/overhaul-1d-habits`): Habits and the history page in
     the card style, swipe-to-delete with Undo on history rows and Undo on the editor's delete (the register's
     inconsistent-delete item is gone), Archive and Edit habit moved to the history page. Left: the amount sheet
     (a held wedge still opens the record dialog, and the editor keeps its form), the history page's "Last 30 days"
     summary card, and page transitions (1f).
   - **e. Auth and settings screens:** one sign-in screen with a segmented control and the password checklist;
     Settings and Account Settings in the card style. Copy stays as it is until `r3-delete-copy`. In review (`feat/overhaul-1e-account`): all of it, plus
     the 3:1 keyboard focus ring on card rows, the sign-in segments and the slider (a 2 pt accent ring in place of
     Material's 12% overlay); the unused navigation-bar themes are gone with the sign-in BottomNavigationBar. Left:
     the Habits and history `ListTile`s (1d's files) still show only Material's overlay; Settings has no Export or
     Reduce motion row (Export stays in Account Settings; nothing to set for motion yet). Side by side in
     `fidelity/signin-*`, `signup-*`, `settings-*` (`test/fidelity_account_render_test.dart`).
   - **f. Motion polish:** bead travel, day sweep, springs, page transitions (the mock-up's notes add the
     `animations` package), and the reduce-motion fades.
   - **g. e2e rewrite:** rebuild `integration_test/` around the new flows (fan gestures, dial semantics, the sheets),
     on iOS and `E2E_DEVICE=macos`.
2. **The macOS split view** (`notes.md`, "macOS"): dial and tallies left, Trends right, from 900 pt. In review in
   #92 (`feat/macos-split-view`): width-based, so an iPad on its side gets it too; the Log button
   sits at the foot of Today's column, a chart day moves Today's dial, Left and Right step days. The Mac window still
   opens at 800×600 (phone layout), so the macOS e2e suite keeps testing the sheet;
   `integration_test/split_view_test.dart` lays the app out at 900, 1200 and 1600 pt.
3. **Bundle IDs to `com.screendead.penchant`: done** (#84, merged 2026-11-06): iOS and
   macOS, Runner and RunnerTests, the Penchant `GoogleService-Info.plist` on both platforms, `firebase_options.dart`,
   the macOS keychain group. The idea file is deleted; what it had left (the domain variant, an App Store search on a
   device) moved to the support-pages and TestFlight ideas and to For Jack to do. iOS e2e 31/31 and a signed release
   build pass, and the review's full `E2E_DEVICE=macos tools/e2e.sh` (2026-11-06, load about 7) passed 31/31 with
   34 registrations. Earlier runs under load 40 and up had 3 of 70 registrations time out at 30 s (Homepage never
   appeared), beside other 30 s timeouts that touch no Auth code (a server count, a dialog close); a load effect, not
   a keychain one, is the likelier reading. If the hang comes back on a quiet machine, the macOS keychain access group
   (`macos/Runner/*.entitlements`) is the one ID-specific piece on Auth's persistence path.
4. **The work from the 2026-11-06 picks** (rounds 2 to 4 and 8, below). Small ones first: `r8-clear-spokes` B (major
   spokes to 25% on a clear day, classed as decoration in `contrast-pairs.json`), `r4-weekly` B (round down to whole
   weeks; deletes the register's oldest-weekly-bucket item), `r8-mac-keys` B (Cmd-1 to Cmd-9 log one, in the menu
   bar), `r8-mac-window` B (about 1200 x 780, with 1g), Crashlytics (`r2-crash` A), guest start with linking an email
   later (`r2-signin`, the part that needs no paid Apple team), onboarding with the plain-name presets (`r2-presets`
   A), the data model's decimal amount and vice category with its first-launch migrator (`r2-data-model` B), trigger
   tagging with the Areas of life tree (`r2-triggers` A), and end-to-end encryption (`r2-e2ee` A, `r2-e2ee-key` A).
   Waiting on Jack before any build: the precomputed per-user summary that `r8-bead-size` asks for (no server code
   exists; see the call) and Sign in with Apple (the paid team).
5. **The rest of the register**, medium then low, one class per PR.

### This run (`/finish-and-pitch`, second pass, started 2026-11-06)

The first pass (waves A to D) is merged. CI was down on 2026-11-06 (Actions billing limit) until Jack made the repo
public and renamed it `Screendead/penchant` the same day; public repos run standard Actions runners free. #83 merged.

**DECIDED** (in order; code PRs open and stack, and merge once CI is back or Jack waives it):

- **Track A, the overhaul, stacked on #83:** 1c Trends sheet, then 2 macOS split view, then 1d Habits/history/editor
  (with the amount sheet, swipe-to-delete with Undo, which also settles the register's inconsistent-delete item),
  1e auth and settings (with keyboard focus on list rows, navigation destinations and the slider, which #82 found at
  about 1.2:1), 1f motion polish, 1g e2e rewrite. One PR each, on top of the last.
- **Track B, Apple platform debt, off `master`:** ~~the CocoaPods sunset~~ (done in the PR from
  `chore/swift-package-manager`: both platforms on Swift Package Manager, no Podfile left), ~~the failing
  `flutter build macos --release`, the legacy signing config and the dead scaffold assets~~ (done in the PR from
  `chore/apple-build-config`, stacked on #87). The release build needs Flutter 3.44.8 or later (flutter/flutter#188346,
  Xcode 27's `lipo`): CI's pin is 3.44.9, and the machine's Homebrew Flutter (3.44.7) moves to 3.44.9 when no agent
  is mid-build; 3.44.9 sits at `~/development/tracker-tools/flutter-3.44.9` meanwhile. 3.47 (Dart 3.13, riverpod_lint
  3.1.9) is a separate step.
- **Track C, reliability and tooling, off `master`:** a refused write queued by an earlier launch is dropped silently
  (PR #88 from `fix/rejected-write-earlier-launch`, reviewed: a journal on the device, checked on the next launch);
  the minimatch override breaks firebase-tools glob paths; nothing checks the index file against the queries
  (both done in PR #90 from `chore/minimatch-and-index-check`, stacked on #88: a range-keyed override, and
  `test/firestore_indexes_test.dart`; no app change, so no e2e).
- **Docs:** land `design/day-dial-system` (the published design system's sources) on `master`.

**UNDECIDED:** the three calls 1d and 1e raised (Calls waiting on Jack, below), and the design of `r8-bead-size`'s
precomputed summary. Every call on the pitch page is picked (2026-11-06). `r7-ci` and round 5 are moot and off the
page. Other languages are still unasked.

**Blocked on Jack, not decisions:** none while there is no paid Apple team and no release (Jack, 2026-11-06): App
Attest, TestFlight, the App Store, Sign in with Apple and the domain wait on those, and the privacy-policy details are
skipped (`r2-privacy`).

Housekeeping that rides along with whatever PR touches it: delete each tech-debt file a PR fixes, and each idea file
a PR ships, with its README line; run `tools/tech-debt-recount.py` to fix the counts. It resolves paths from its own
location, so run the copy inside the worktree you are changing.

## Jack's calls, round 1 (2026-11-03)

Picked on the pitch page; the page keeps the options and costs each was chosen from.

- **C1. Rules deployment** (`rules-deploy`): **CI deploys rules and indexes on merge to `master`.** So every rules PR
  Claude merges reaches production; the rules tests gate it. On since 2026-11-04.
- **C2. Today with 1 or 2 vices** (`today-few-vices`): **bars below 3 vices, the radar from 3 up.** Superseded by
  `r6-ui-direction` (2026-11-05): the radar leaves Today, and with it the bars rule, once overhaul step 1b lands.
- **C3. Save timeout** (`record-timeout`): **close the dialog and say the entry will sync.**
- **C4. Undo duration** (`undo-duration`): **8 seconds.**
- **C5. Clean day** (`clean-day`): **quietly positive**: a green tint and short encouraging copy, no streak pressure.
- **C6. Platforms** (`platforms`): **iOS first, through TestFlight.** "Delete the rest. Add a MacOS target too,
  fully-supported." Android and web go.
- **C7. `functions/`** (`functions`): **delete it** and close its Dependabot PRs.
- **C8. Licence** (`licence`): **proprietary, all rights reserved.**
- **C9. Stale git state** (`git-cleanup`): **archive the stashes, then clean**; keep `copilot/fix-9`.
- **C10. E2E in CI** (`e2e-ci`): **in CI on `master` after merge, debounced** (Jack, 2026-11-06, superseding "local
  only"): `e2e.yml` (#96); PRs merge on the PR checks, and a red run on `master` is fixed forward first.
- **C11. PR previews** (`pr-previews`): **drop them.** Moot once web goes (C6).
- **C12. Quantity** (`quantity`): **greater than 0** on a new activity. So a free day is not logged as a zero entry.
- **C13. Vice name length** (`name-length`): **60 characters at most.**
- **C14. Vice ownership** (`vice-owner`): **check it**: an activity's vice must belong to the person logging it.
- **C15. Positioning** (`positioning`): **a neutral journal, for seeing trends and learning about yourself.** Jack's
  note, condensed: the journal and trend side must be significantly shored up; cutting down may coexist, but the
  journal is the point. He wants intelligent insights: what causes use (calendar integration for meetings; triggers
  picked from options that get more specific as you click through, remembering your most common ones, or free text);
  what follows from using one vice against another (Apple Health: sleep, HRV, heart rate and the like, including
  historical data, disambiguating which vice a health effect correlates with over time). Maximum granularity.
  Privacy is not a concern as long as sensitive processing and storage stay on the device; it can all be regenerated
  from the raw data.
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer. Apple retired 17+ in July 2025; Jack confirmed
  18+ (`r2-age`, 2026-11-06).
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes.** Optional fields are fine. Mandatory fields are allowed too,
  but only with a migrator that runs on first launch and adds them to existing records.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** The brand is Penchant (`r2-brand`, round
  2 below).

## Jack's calls, round 2

- **`r2-web-site`** (2026-11-03, in chat): **take the live web site down now.** Claude can't: it is Firebase Hosting
  on the production project, which the hard rules put out of Claude's reach, so Jack did it; the site returns 404
  (checked 2026-11-04). Done.
- **`r2-icon`** (2026-11-05, in chat): **candidate 38**, the Today radar's coloured segments with spokes running past
  them, centred, on a light background. Picked from 38 candidates on the icon sheet
  (https://claude.ai/artifact/JGnHCcPxaTLHKiyZeFgNmK, sources on `mockup/icon-sheet`). Shipped as the iOS and macOS
  icon in the PR that records this; the sources are `assets/icon.svg` and `assets/icon-macos.svg`. Independent of the
  brand. Done.
- **`r2-brand`** (2026-11-05, on the pitch page https://claude.ai/artifact/NBsbWYMVPh2phzS3wKDRCH, no note):
  **Penchant**, with the recommended App Store subtitle **"Habit journal & sleep insights"**. Applied to every
  identity string by #81; the bundle IDs followed in `feat/bundle-id-penchant`. Backups if the name proves unusable: Kenning, then Sounding.
- **`r2-presets`** (2026-11-06): **A, the plain names** (Alcohol, Coffee, Cigarettes, Vape, Cannabis, Energy drinks,
  Sweets, Gambling) in a first-run flow for an account with no habits: intro, presets plus "Something else", the
  disclaimer, an optional first log. Built in the PR from `feat/onboarding-presets` (`lib/onboarding/`).
- **`r2-mac-config`** (2026-11-05): the Mac shares the iOS app's Firebase registration and config file (the
  recommended side); the console offered no separate macOS app.
- **No trademark search** (2026-11-05, Jack): none will be done, professional or otherwise. Don't raise it again.
- **Wording** (2026-11-05, Jack): the app says **"habits"**, not "vices", in its UI. Code, routes, Firestore
  collections and fields, and the export's column names keep `vice`, so the data shape is unchanged
  (#81).

## Jack's calls, round 6

- **`r6-ui-direction`** (2026-11-05, on the UI overhaul pitch page https://claude.ai/artifact/23uvjtPyS7TqPvXaEBw9Px;
  read from its `picks` collection): **Day Dial**, the day as a 24-hour dial with each entry a coloured bead at its
  time. This also settles **`r2-today`**: the radar leaves Today, so C2's bars-below-3 rule is
  superseded, and it allows the one-tap **"log one"** action (a tally row's `+`, or a tap on a Log-fan segment, logs
  the default quantity now with the 8-second Undo). Chrome is ink on paper; the five icon colours mean habits only.
  A habit's colour is its creation order (archived included) mod 5, rings from the sixth, dotted rings from the
  eleventh; computed on the device, no stored field. Units stay the existing enum; new units are `r2-data-model`.
  Built as the queue's item 1.
- **Contrast** (2026-11-05, in chat): **every colour pair meets the accepted accessibility minimum in both themes**,
  WCAG 2.2 AA: 4.5:1 for text, 3:1 for icons, meaningful graphics, control edges and focus. Fix, never flag; the
  habit colours keep the icon's five hues (lightness, rims and inks may change). The pairs are
  `docs/design-system/day-dial/project/contrast-pairs.json`, checked by `tools/contrast-check.py` and
  `test/contrast_test.dart`; a new use of a colour adds its pair there.

## Jack's calls, rounds 2 to 4 and 8 (2026-11-06)

Picked on the pitch page (https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs); the page keeps the options and costs.
Notes are Jack's, condensed.

- **`r2-privacy`**: **no privacy policy for now.** Not going on the App Store; it is just for him. Treat it as a
  production project and give it the polish, but the legal details stay undone until and unless he decides to sell.
- **No paid Apple Developer account for now** (Jack, 2026-11-06): no TestFlight, App Store or App Attest yet; the
  domain variant waits until a release.
- **`r2-testflight`**: **Production** (no separate beta project). "Just Do It Right." Moot until there is a paid team.
- **`r2-signin`**: **guest start, link an account later, plus Sign in with Apple.** Jack's production data sits under
  an email-and-password account and has to end up on his Apple ID (Sign in with Apple). Linking the Apple credential
  to the signed-in email user keeps the uid, so the data needs no copy. Sign in with Apple needs the paid team; guest
  start and linking an email do not.
- **`r2-e2ee`**: **yes, before 1.0**: names, units, amounts and later notes sealed on the device (AES-256-GCM); dates,
  IDs and the owner stay plaintext. Key in iCloud Keychain plus a printable recovery key.
- **`r2-e2ee-key`**: **a Today card after a week, and Settings any time.**
- **`r2-data-model`**: **optional fields, plus a first-launch migrator (for a vice category) and a decimal amount**
  next to the whole-number quantity.
- **`r2-days`**: no option picked; the call: **if nothing is logged, treat the day as clean.** No check-in and no
  days collection.
- **`r2-presets`**: **plain names** (Alcohol, Coffee, Cigarettes, Vape, Cannabis, Energy drinks, Sweets, Gambling).
- **`r2-triggers`**: **Areas of life** (Social, Feeling, Work, Body, Routine, Place, Craving), against the
  recommended B.
- **`r2-today`**: A (the journal layout), superseded by `r6-ui-direction`: Today is the Day Dial. No work.
- **`r2-brand`**: **Penchant** (already applied). **`r2-brand-icon`**: "We already have a brand I like": the icon
  stays `r2-icon`'s candidate 38. No work.
- **`r2-age`**: **18+**. **`r2-mac`**: **the Mac ships with iOS 1.0 if its e2e is green.** Both moot until a release.
- **`r2-pro`**: **the analysis layer, $24.99**. **`r2-billing`**: **StoreKit 2 directly.** **`r2-applock`**: **app
  lock and discreet mode both free.** Parked with the store work; nothing to build now.
- **`r2-crash`**: **Crashlytics only.**
- **`r2-cli`**: **upgrade the global Firebase CLI** (`npm install -g firebase-tools@latest`).
- **`r3-delete-copy`**: **ship the deletion wording as written.** **`r3-verify`**: **nothing requires a verified
  email.** **`r3-cache`**: **keep the on-device cache.** **`r3-attest`**: **App Attest with DeviceCheck fallback, as
  built.** All as built; no work.
- **`r4-server-time`**: **the phone's clock, as built.** **`r4-vice-cap`**: **no cap for 1.0.** No work.
- **`r4-weekly`**: **round the range down to whole weeks** (30 days shows 28), against the recommended A. Queued.
- **`r8-clear-spokes`**: **25%, as the mock-up**, against the recommended A: on a clear day the major spokes are
  decoration (the 00/06/12/18 labels give the time), an exception to the contrast rule for that state only. Queued.
- **`r8-coach`**: **don't build the "Tap Log" pill.**
- **`r8-bead-size`**: C, **a typical amount stored per habit**, on Jack's terms: not editable, populated by a
  scheduled job each month over the last 3 months only. More generally, precompute wherever possible into a single
  document per user, to cut reads and load times, especially for the graph and calendar. The app has no server code
  (`functions/` was deleted by C7), so how the job runs is open (below); nothing is built until then.
- **`r8-tally-target`**: **44 x 38, as built.** No work.
- **`r8-mac-window`**: **about 1200 x 780, the split view by default**; lands with 1g.
- **`r8-mac-keys`**: **Cmd-1 to Cmd-9 log one of the Nth habit now**, listed in the menu bar. Queued.

## Calls waiting on Jack (UNDECIDED)

Not on the pitch page yet; each is built one way and waits on a pick.

- **Archive placement** (from 1d): Archive moved from Manage Data to a button on the habit's history page (as built).
- **Appearance** (from 1e): Settings has a fixed "Match system" row; the theme follows the system with no light or
  dark override (as built).
- **Export** (from 1e): Export lives in Account Settings only; Settings has no Export row (as built).
- **How `r8-bead-size`'s summary is computed**: a scheduled server job needs Cloud Functions back (C7 deleted them),
  the Blaze plan and a CI deploy path for functions, and it cannot read amounts once `r2-e2ee` seals them. The
  smallest alternative is the app refreshing the user's summary document itself on launch when it is over a month
  old (no UI, so not editable; the rules fix its fields).

Round 5 (`r5-radar-inset`, `r5-key-height`, `r5-key-always`) is moot: the radar and its key left Today in #83.

## For Jack to do (not decisions)

Jack reported the page's list done on 2026-11-06. Checked from here: Dependabot PRs #22 and #42 are closed, and the
CLI's configstore no longer maps the main checkout to production (`firebase use --clear` done). The console steps
(Email Enumeration Protection, the email templates, a budget alert) can't be seen from here; taken as done on his word.

- **Still open:** the main checkout still shows `macos/Runner.xcodeproj/project.pbxproj` modified (the 2026-11-04
  signing attempt; #47 carries the team). `git checkout -- macos/Runner.xcodeproj/project.pbxproj` in
  `~/development/tracker` discards it; Claude leaves it, as it is Jack's working tree.
- **Waits on a paid Apple Developer Program team, which Jack is not getting for now** (2026-11-06): the App Attest
  entitlement (a personal team can't sign it; once there is a team Claude adds
  `com.apple.developer.devicecheck.appattest-environment` = `production` and proves the release build signs),
  registering the app with App Check (Team ID, a DeviceCheck key) and then enforcing it on Firestore, TestFlight, Sign
  in with Apple, and the App Store.
- **Waits on a release:** the domain variant (`penchant.com` is held, `penchant.app` parked) and the support and legal
  pages it addresses, an App Store search for Penchant, and the privacy-policy and support details (`r2-privacy`).
- **The old app install:** the build under `com.screendead.tracker.tracker` stays on the phone beside Penchant until
  deleted; its two iOS registrations in the console can go once it is.
- **Indexes:** the activities index is deployed; production also holds 4 indexes `firestore.indexes.json` doesn't
  list, left in place (the register's index-drift item).

## How to test here

- **Never against production.** Emulators run with `--project demo-tracker`; see `CLAUDE.md` "Hard rules".
- `tools/e2e.sh` runs `integration_test/` on an iOS Simulator (an "iPhone 18 Pro", or `$E2E_DEVICE`) against the
  Auth and Firestore emulators. `tools/run-emulated.sh` launches the app against them for a manual look.
- `npm --prefix tests/firestore-rules test` runs the rules suite; CI runs it on every PR.
- Only one agent at a time may use the simulator and the default emulator ports. Parallel agents that need an
  emulator use other ports (Firestore 8180, hub 4410, logging 4510, UI off) through a config outside the repo.
- `macos/Flutter/GeneratedPluginRegistrant.swift` is tracked (iOS gitignores its own; in the register).
  `flutter pub get` rewrites it only when the plugin set changes; commit the rewrite with the change that caused it.
- Read the Firebase documentation before any change to rules, indexes, queries or emulator wiring, and cite it in
  the PR.

## Where the backlogs are

- `tech-debt/README.md` — what is wrong, by class and severity. Non-prescriptive; the fix is the PR's to design.
- `ideas/README.md` — what to build next, as pitches with a recommendation each, ordered as a roadmap to a paid
  release. Items marked "Needs Jack: yes" go to him as pitches before they are built.

## Thoughts

- The app is a small Flutter + Firestore codebase (about 3,000 lines in `lib/`). Tests now exist at three levels
  (rules tests, unit and widget tests, 31 e2e tests), but most of the app is still untested. Most of the work before release is making it trustworthy, not adding screens.
- Firestore writes go through `TrackerWrites` (`trackerWritesProvider`), so widget tests cover every write path with
  a fake; Auth calls go through `Account` (`accountProvider`) the same way.

## Set aside, with reasons

- **Rebasing or force-pushing the recovered feature branch** to tidy its history: it was already pushed, and
  force-pushing needs Jack. It merges `master` in instead.
- **Android release, the web app, Cloud Functions, PR previews** (C6, C7, C11): removed 2026-11-03; re-add only on a
  new call.
- **Harm-reduction framing, and the moderation, alcohol-only and quit-counter positionings** (C15, C16): the app is a
  neutral journal. Goals and limits survive as an optional, later feature.
