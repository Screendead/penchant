# Handover — Tracker

*Updated 2026-11-05. Audience: the next agent, or Jack. This file holds the current task: the queue, where each item
stands, the calls waiting on Jack, and the options set aside. Update it in the same commit that closes an item or
records a call. Git holds the history. How the code works lives in `CLAUDE.md`.*

## The goal

Release the app on the App Store and make money from it. The road there runs in this order: make what exists work
(the bugs Jack hit), make it safe to change (emulators, end-to-end tests, CI gates), burn down the debt that blocks a
release, then build the release prerequisites and the paid product from `ideas/`.

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
| UI overhaul: Day Dial (`r6-ui-direction`, Jack 2026-11-05) | Step 1a, the theme foundation, in #79: tokens, light and dark themes following the system, bundled Red Hat fonts, habit colours by creation order. The screens are unchanged in layout | `lib/design/`, `assets/fonts/` |
| Round-2 calls (16, plus `r2-e2ee` and `r2-mac-config` added later), round 3 (`r3-*`, 4 calls), round 4 (`r4-*`, 3 calls) and round 5 (`r5-*`, 3 calls) | Open on the pitch page; rounds 2 and 3 since 2026-11-03, 4 and 5 since 2026-11-04 | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Tech-debt register | 23 issues on master: 0 critical, 0 high, 12 medium, 11 low (`tools/tech-debt-recount.py`, 2026-11-05; from 162 on 2026-08-11) | `tech-debt/README.md` |
| Product backlog | 31 ideas for the journal positioning (versioning, offline-first, account deletion and export shipped), roadmap in its README | `ideas/README.md` |

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
   name strings stay until `r2-brand` (the mock-up's "Tracker" is a placeholder).
   - **a. Theme foundation:** tokens, light and dark `ThemeData` with `themeMode: system`, bundled fonts, the habit
     colour function, the hard-coded colours replaced. In review (#79).
   - **b. Today:** the dial (`CustomPainter`, beads at their times, now-hand, clear-day ring), the tally rows with a
     `+` each, the one-tap "log one" action (the default quantity, now, with C4's 8-second Undo; this was the
     layout-neutral half of one-tap logging), the Log button and its fan, the amount sheet that replaces the record
     dialog for new entries, and the calendar sheet. The radar and C2's bars leave Today.
   - **c. Trends sheet:** a `DraggableScrollableSheet` over Today that replaces the Graph tab: habit chips, range and
     Day/Week segments, the average stepper, stats, "when it happens", and a day point opening its dial.
   - **d. Habits, history and the entry editor:** Manage Data becomes Habits, the history list gets swipe-to-delete
     with Undo, and editing reuses the amount sheet.
   - **e. Auth and settings screens:** one sign-in screen with a segmented control and the password checklist;
     Settings and Account Settings in the card style. Copy stays as it is until `r3-delete-copy` and `r2-brand`.
   - **f. Motion polish:** bead travel, day sweep, springs, page transitions (the mock-up's notes add the
     `animations` package), and the reduce-motion fades.
   - **g. e2e rewrite:** rebuild `integration_test/` around the new flows (fan gestures, dial semantics, the sheets),
     on iOS and `E2E_DEVICE=macos`.
2. **The macOS split view** (`notes.md`, "macOS"): dial and tallies left, Trends right, from 900 pt. After 1c; the
   mock-up does not show it.
3. **Round-2 calls, once picked**: record each below with the date, then queue its work. Build nothing on an unpicked
   call. Read the picks with `ArtifactData` `list` on collection `picks` of the pitch page (ids start `r2-`).
4. **The rest of the register**, medium then low, one class per PR.

### This run (`/finish-and-pitch`, started 2026-11-03)

Waves A to D are merged (the table above has each). Of round 2 only `r2-web-site` and `r2-icon` are picked, and
`r2-today` is settled by `r6-ui-direction`. Left over:

- Left for Jack's calls: brand strings, telemetry, verified email, vice cap, other languages. The "log one" action
  is decided by `r6-ui-direction` and lands in overhaul step 1b.
- **Builds for the open calls**, beside the waves, on `mockup/*` branches: Today layout, onboarding presets, the
  trigger tree, brand and icon candidates. They go on the pitch page with screenshots.

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
- **C10. E2E in CI** (`e2e-ci`): **local only**; Claude runs `tools/e2e.sh` before each merge.
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
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer. Apple retired 17+ in July 2025; round 2
  (`r2-age`) asks Jack to confirm 18+.
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes.** Optional fields are fine. Mandatory fields are allowed too,
  but only with a migrator that runs on first launch and adds them to existing records.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** The brand itself is open on the pitch page (`r2-brand`;
  candidates in `ideas/release-blockers/brand-name.md`).

## Jack's calls, round 2

- **`r2-web-site`** (2026-11-03, in chat): **take the live web site down now.** Claude can't: it is Firebase Hosting
  on the production project, which the hard rules put out of Claude's reach, so Jack did it; the site returns 404
  (checked 2026-11-04). Done.
- **`r2-icon`** (2026-11-05, in chat): **candidate 38**, the Today radar's coloured segments with spokes running past
  them, centred, on a light background. Picked from 38 candidates on the icon sheet
  (https://claude.ai/artifact/JGnHCcPxaTLHKiyZeFgNmK, sources on `mockup/icon-sheet`). Shipped as the iOS and macOS
  icon in the PR that records this; the sources are `assets/icon.svg` and `assets/icon-macos.svg`. Independent of the
  brand. Done.

## Jack's calls, round 6

- **`r6-ui-direction`** (2026-11-05, on the UI overhaul pitch page https://claude.ai/artifact/23uvjtPyS7TqPvXaEBw9Px;
  read from its `picks` collection): **Day Dial**, the day as a 24-hour dial with each entry a coloured bead at its
  time. This also settles **`r2-today`**: the radar leaves Today, so C2's bars-below-3 rule is
  superseded, and it allows the one-tap **"log one"** action (a tally row's `+`, or a tap on a Log-fan segment, logs
  the default quantity now with the 8-second Undo). Chrome is ink on paper; the five icon colours mean habits only.
  A habit's colour is its creation order (archived included) mod 5, rings from the sixth, dotted rings from the
  eleventh; computed on the device, no stored field. Units stay the existing enum; new units are `r2-data-model`.
  Built as the queue's item 1.

## Calls waiting on Jack (UNDECIDED)

Round 2 is on the pitch page, https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs, each with options and one
recommendation. Ids: `r2-e2ee` (end-to-end encryption of what each entry says; `ideas/release-blockers/end-to-end-encryption.md`,
prototype on `mockup/e2e-encryption`; Jack's steer 2026-11-03: encrypt names and quantities, dates may stay plaintext),
`r2-mac-config` (the macOS Firebase config: reuse the iOS app's registration, recommended, or register a separate
app), `r2-brand`, `r2-trademark`, `r2-age` (18+ in
place of the retired 17+), `r2-data-model` (fields on activities, decimals, new collections), `r2-days`, `r2-mac`,
`r2-pro` (the free/Pro line and price), `r2-billing`, `r2-signin`, `r2-crash`, `r2-testflight` (a separate beta
Firebase project), `r2-privacy`, `r2-applock`, `r2-cli` (upgrade the global Firebase CLI).

Built as mock-ups on branches and pitched with screenshots: the Today layout (`mockup/today-layout`), the onboarding
presets and wording (`mockup/onboarding-presets`), the starter trigger tree (`mockup/trigger-tree`), and brand plus
icon (`mockup/brand-and-icon`, for `r2-brand`; its icon half is superseded by `r2-icon`). Ids `r2-presets`,
`r2-triggers`; `r2-today` is settled by `r6-ui-direction`.

Round 3 (2026-11-03, raised by wave B): `r3-delete-copy` (the deletion and export wording in
`lib/account/account_copy.dart`), `r3-verify` (whether anything requires a verified email), `r3-cache` (keep the
on-device cache for offline logging, which Firebase says is not securely wiped), `r3-attest` (App Attest with
DeviceCheck fallback, as built, or DeviceCheck only).

On the pitch page as `r4-vice-cap`: **`vice-cap`** (from backend hardening, PR #55): cap the number of vices per user, with a
guard in Add Vice and the rules, or leave the vice lists unbounded. Claude's recommendation: **leave them unbounded
for 1.0**: vices are created by hand, and since the day query dropped its `in` filter the number of vices limits no
query. A bare `limit` is not an option: it would hide the oldest vices without saying so. Register:
`tech-debt/firebase-data-layer/vice-lists-are-unbounded.md`; idea: `ideas/release-blockers/backend-hardening.md`.

On the pitch page as `r4-weekly`: **`weekly-remainder`** (from the usage graph fix, PR #69): Weekly view covers every day
the Range menu names, counted back from today, so the newest point is a whole week and, when the range is not a
whole number of weeks, the oldest point sums only the days left over (2 at 30 days, 6 at 90, 5 at 180, 1 at 365)
and reads low. On master the short bucket was the newest one. Options:
- **A** keep the partial oldest bucket, labelled as partial on the axis and in the summary;
- **B** round the range down to whole weeks (drops up to 6 days of the named range);
- **C** round it up to whole weeks (shows up to 6 days more than the menu says);
- **D** scale the partial bucket to a weekly rate (marked as estimated).

PR #69 ships the unlabelled form of A. Claude's recommendation: **A** (keep the short oldest week, labelled as
partial). Register:
`tech-debt/widget-state-and-view-logic/oldest-weekly-bucket-holds-the-remainder.md`.

On the pitch page as `r4-server-time`: **`server-time`** (from the data-layer PR, #68): stamp "now" entries with
`FieldValue.serverTimestamp()`, or keep the device clock. The queued item asked for server time; #68 kept the device
clock. A pending server timestamp matches no `createdAt` range query, so an entry logged offline is missing from Today
until it syncs, and the server stamps the sync time, so it can land on another day. Claude's recommendation: **keep
the device clock**, since offline logging (#53) is shipped; the cost is that a skewed or hand-set clock places an
entry anywhere, which the rules don't bound. Register:
`tech-debt/firebase-data-layer/activity-timestamps-come-from-the-device-clock.md`; rule: `CLAUDE.md` **Days**.

Round 5 (2026-11-04, from the Today chart fix, PR #74; on the pitch page, each built the first way). Recommendations,
not decisions. All three concern the radar's key, which leaves Today in overhaul step 1b, so they are likely moot
once it lands; they stay open until Jack says so:
- **`r5-radar-inset`**: radar inset by one title line on every side at all text sizes (recommended, as built) vs only
  when the key shows.
- **`r5-key-height`**: the key takes the height it needs and the chart is left out below four title lines of room
  (recommended, as built) vs a half-height cap with scrolling vs bars instead of the radar at large text sizes, with
  the key when bar names still don't fit (bars also need a name per bar, so the largest size still falls back to the
  key; a day's work).
- **`r5-key-always`**: also show the key whenever amounts are dropped from titles (**yes**, recommended) vs only when
  a name is cut.

## For Jack to do (not decisions)

- **Web site taken down** (`r2-web-site`): done; the site URL returns 404 (checked 2026-11-04). The deployed
  releases stay in the console, so this can be undone.
- **Mac development profile**: done by Jack 2026-11-05; the macOS e2e passes on #47. The main checkout may still
  hold an uncommitted `macos/Runner.xcodeproj/project.pbxproj` from the 2026-11-04 attempt; #47 carries the team, so
  `git checkout -- macos/Runner.xcodeproj/project.pbxproj` there discards it.
- **Close Dependabot PRs #22 and #42** if Dependabot hasn't: #44 supersedes them, and closing them was refused to
  Claude (`gh pr close 22 42`).
- **The activities index is deployed** (Claude, 2026-11-03, with Jack's leave to deploy indexes only, never
  `--force`). Before installing a build from #55 on, confirm Firestore > Indexes shows `activities (ownerID ASC,
  createdAt DESC)` **Enabled**. Production also holds 4 indexes that `firestore.indexes.json` doesn't list; they were
  left in place (the register's index-drift item).
- **App Attest needs a paid Apple Developer Program team.** Adding the App Attest entitlement to Runner broke
  `flutter build ios --release`: Xcode said "Personal development teams, including "Jack Lusher", do not support the
  App Attest capability" for team 8N575942RT, so the backend-hardening PR ships App Check without it, and App Attest
  yields no accepted token until it is added. TestFlight needs the paid membership anyway. Once the team has it, tell
  Claude: it adds the capability (`com.apple.developer.devicecheck.appattest-environment` = `production`) and proves the
  release build still signs.
- **Register the iOS app with App Check** (waits on the paid Apple team; Jack: "can wait") (Firebase console > Security > App Check > Apps): App Attest (needs the
  Team ID) and DeviceCheck (needs a DeviceCheck key from the developer portal: the .p8 file, its Key ID, the Team ID).
  Enforce nothing yet.
- **Enforce App Check on Firestore only after every installed copy has it:** your iPhone and every TestFlight
  tester on a build from the backend-hardening PR or later, the App Attest entitlement in place, and Security >
  App Check > APIs showing nearly all Firestore requests verified. An older build is refused once you click
  Enforce; enforcement takes up to 15 minutes, and turning it off undoes it.
- **Set budget alerts** on `screendead-vice-tracker` (Google Cloud console > Billing > Budgets & alerts, or the
  prompt when upgrading to Blaze). Alerts only email; they don't pause Firestore.
- **Check Email Enumeration Protection is on** (Firebase console > Authentication > Settings > User actions, for
  `screendead-vice-tracker`). The app no longer shows Firebase's error text, but with protection off the Auth API
  itself still answers "no such user" differently from "wrong password". Also check the password-reset and
  verification email templates read sensibly now that the app sends both.
- **Clear the main checkout's active Firebase project** (from #68): in `/Users/jacklusher/development/tracker`, run
  `firebase use --clear`. The CLI's configstore maps that directory to `screendead-vice-tracker`, and that entry wins
  over `.firebaserc`, so until it is cleared a bare `firebase deploy` or `firestore:*` there reaches production. It
  edits only the local configstore and calls nothing in any project; afterwards `firebase use` there prints
  `demo-tracker`. Register: `tech-debt/firebase-data-layer/every-firebase-command-targets-production.md`.
- **Send Claude in chat:** the privacy policy's legal entity, contact address and data-controller details; the
  support email; the TestFlight testers. They stay out of the repo.

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
