# Handover — Tracker

*Updated 2026-11-08. Audience: the next agent, or Jack. This file holds the current task: the queue, where each item
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
| UI overhaul: Day Dial (`r6-ui-direction`, Jack 2026-11-05) | 1a to 1e merged: 1a #79, 1b #83 with the fidelity pass #94, 1c #89, 1d #100, 1e #99 (2026-11-05/06). 1f partly (#98) and 1g partly (#119); what is left is in the overnight list (D1 to D5) | `lib/design/`, `assets/fonts/`, `lib/widgets/day_dial.dart` |
| Rounds 2, 3, 4 and 8 on the pitch page | All picked by Jack 2026-11-06, and round 9 on 2026-11-07, recorded below; round 5 is moot (the radar left Today in #83) | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Brand: Penchant (`r2-brand`) and "habit" wording | Applied to the app's strings in #81 (2026-11-05). Bundle ID `com.screendead.penchant` on iOS and macOS with the new Firebase config, shared by the Mac (`r2-mac-config`), merged in #84 (2026-11-06); both development profiles exist, and a signed `flutter build ios --release` carries the new ID | `lib/firebase_options.dart`, `ios/`, `macos/` |
| End-to-end encryption (`r2-e2ee`, `r2-e2ee-key`) | On: merged in #130 (2026-11-08), after the crypto core (#115), sealed fields (#117), the migrator (#114), the key UI (#116) and the key service (#124). The post-merge e2e run on a2b5c30 passed. Why the key did not sync from iPhone to Mac is in progress (`fix/journal-key-sync`) | `lib/crypto/` |
| Tech-debt register | 11 issues: 0 critical, 0 high, 4 medium, 7 low (`tools/tech-debt-recount.py` on `master`, 2026-11-08; from 162 on 2026-08-11) | `tech-debt/README.md` |
| Product backlog | 27 idea files, some for work that has shipped (overnight list, D14) | `ideas/README.md` |
| Cloud Functions | Deployed by CI: Jack set `DEPLOY_FUNCTIONS=true` (2026-11-07), and run 42410165620 created `dailyOrphanCleanup` (a dry run) and updated `monthlySummaries` | `functions/`, `.github/workflows/functions.yml` |

Baseline: CI runs `dart analyze`, the `dart format` check, `flutter test` and the rules tests on every PR, and the
iOS e2e suite on `master` after merge (C10, `e2e.yml`). `flutter build macos --release` last passed in CI on
2026-11-05 (`macos-build.yml`, Flutter pin) and fails with this machine's Homebrew Flutter (overnight list, D9).

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's calls below. Work it top down; skip what is blocked
and say so. Items under one number can run in parallel in separate worktrees; only one agent at a time runs
`tools/e2e.sh` or uses the default emulator ports. Subagents write PR bodies to uniquely named scratchpad files: the
scratchpad is shared, and a generic `pr-body.md` once put one PR's description on another.

1. **The Day Dial UI overhaul** (`r6-ui-direction`, below). The source of truth is the folder
   `docs/pitch/mockups/ui-overhaul/day-dial/` on `master` (landed from `design/ui-overhaul-day-dial`, which
   `r10-pitch-branches` C archives as the tag `archive/design/ui-overhaul-day-dial`): `index.html` (the live
   mock-up), `tokens.json` (mirrored in `lib/design/tokens.json`), `notes.md` (how each part is built in Flutter) and
   the stills. One PR per step, in order; every screen keeps working between steps, and each PR keeps
   `tools/e2e.sh` green by updating the tests its screens break. Habit names in examples are made up; the product
   name is Penchant (`r2-brand`; the mock-up's "Tracker" is a placeholder).
   Status 2026-11-08: 1a to 1e are merged; 1f and 1g are partly done. The "in review" notes below are history; what
   is left is D1 to D5 in the overnight list.
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
2. **The macOS split view** (`notes.md`, "macOS"): dial and tallies left, Trends right, from 900 pt. Merged in
   #92 (2026-11-06) (`feat/macos-split-view`): width-based, so an iPad on its side gets it too; the Log button
   sits at the foot of Today's column, a chart day moves Today's dial, Left and Right step days. The Mac window
   opens at 1200×780 (`r8-mac-window` B), so it shows the split view; the minimum is 390×600 and the frame is saved
   as `MainWindow` (`macos/Runner/MainFlutterWindow.swift`). The e2e suite follows whichever layout it gets
   (`splitLayout` in `integration_test/support.dart`): the Mac runs it on the split view, iOS on the sheet;
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
   `r8-bead-size`'s monthly summary is built (PR from `feat/bead-summary-function`): `functions/` is back with one
   scheduled function, and the dial sizes beads against its typicals; it runs only once Jack does the steps under
   For Jack to do. Waiting on Jack before any build: Sign in with Apple (the paid team). Status 2026-11-08: all built
   and merged (#103 to #107, #109 to #118, #124, #130) except `r8-mac-window` (#108, overnight list D7).
5. **The rest of the register**, medium then low, one class per PR.
6. **Soon: iPhone widgets, Control Centre controls and a Mac menu bar app** (Jack, 2026-11-07). Build all of these:
   - **Home and Lock Screen widgets** in every size WidgetKit offers (small, medium, large, extra large on iPad, and
     the Lock Screen's circular, rectangular and inline). One kind shows **last week's usage of every habit**; the
     other **records one usage of one of the top 1, 3 or 8 habits** (the size picks how many).
   - **Control Centre controls** (iOS 18 `ControlWidget`), one button that logs one usage of a chosen habit.
   - **A macOS menu bar app**: the dial at the top and the habits listed below it. Clicking a habit logs one usage
     at the current date and time.

   Constraints, from the code as it stands: these are native Swift targets (WidgetKit, App Intents) because Flutter
   does not run in an extension. Writing an activity needs no key (`viceID`, `quantity`, `amount`, `createdAt` and
   `ownerID` are plaintext under `r2-e2ee`), but showing habit names does, so the extension needs the app's Firebase
   Auth session and the E2EE key through a shared Keychain access group and an App Group. Check whether the free
   signing team can sign App Groups and extensions before building (proven 2026-11-08 on `spike/widget-app-group`,
   commit becdcaf: the free team signs the WidgetKit extension `com.screendead.penchant.widgets` and the App Group
   `group.com.screendead.penchant` on iOS, the app wrote to the group and the widget read it on Jack's iPhone, and
   `tools/add-widget-target.rb` there generates the target; macOS App Groups are available to free teams per Apple's docs, but
   whether sandboxed macOS needs a TEAMID-prefixed group name is unchecked). Read Apple's current WidgetKit, App Intents and ControlWidget docs
   first. Jack's picks of 2026-11-08 (round 10, below) settle the open questions:
   - **Top habits** (`r10-widget-top` D): the most logged in the last 30 days, overridable by hand in the widget's
     settings.
   - **Undo** (`r10-widget-undo` B): a 5-second Undo where you tapped, on each surface (widget, control, menu bar row).
     Whether WidgetKit can hold and revert such a state is unchecked; read Apple's docs first. Claude's fallback, in the pitch's
     recommendation, if it cannot: C (the app's Undo on the Mac menu bar only), said so.
   - **Siri, Shortcuts and the Action button** (`r10-intents` A): the same log intent, built with the widgets.
   - **macOS widgets** (`r10-mac-widgets` A): the same WidgetKit code as a Mac extension, built with the iPhone
     widgets, for the desktop and Notification Centre. It depends on the journal key reaching the Mac (P2).
   The idea file is [widgets-and-shortcuts](ideas/growth-later/widgets-and-shortcuts.md).

### Overnight run (`/finish-and-pitch`, 2026-11-08)

The inventory of open work as of 2026-11-08, from `origin/master` at 82f69f0, the open PRs, the remote branches, CI on
`master`, the register and the backlog. Effort: S under a day, M a day or two, L more.

**In progress, owned by other agents (leave alone):**

- **P1.** Native AppKit auth fields on macOS for Passwords AutoFill, being made less clunky. PR #133
  (`feat/mac-native-auth-fields`).
- **P2.** Why the journal key did not sync from iPhone to Mac through iCloud Keychain. Branch `fix/journal-key-sync`
  (not on `origin` yet).
- **P3.** Mac fullscreen layout pitch, 3 options. `design/mac-fullscreen-a` is pushed; b and c are local worktrees.

**DECIDED** (the goal is set by a recorded call or a convention):

- **D1.** DONE (#148, merged 2026-11-08; the leftovers below are follow-ups). Amount sheet replacing the record dialog for new entries, reused by the entry editor (1b and 1d leftover).
  PR #148: the sheet (title, stepper, pill button) replaces the dialog, and the editor page builds the same
  `AmountFields`. Left: the mini dial for the time, which replaces `ActivityDateField` in the mock-up (next; D2's
  edited bead travel needs it); the step of 5 for habits whose typical entry is 10 or more; the editor as the sheet
  itself rather than a page (with D5, which rewrites the editor e2e flows). `lib/widgets/`. M.
- **D2.** The rest of 1f, as #98's "Left for 1f" lists it: `animations` page transitions, `OpenContainer` for a
  Trends day point, the chart morph between ranges, the offline and refused-write pills on a spring, an edited bead
  travelling to its new time (needs D1), the reduce-motion day fade, the dial's drag snap-back. `lib/widgets/`. L.
- **D3.** A dense hour's beads merge into one arc above about 48 entries (1b leftover). `lib/widgets/day_dial.dart`. S.
  Built in `feat/dense-hour-arc` (stills in `docs/pitch/dense-hour/`): above 48 entries, an hour with more than one
  entry is one arc; an hour's lone entry stays a bead, pushed clear of the arcs. The arc draws no pending rim for
  unsynced entries in it (register, `dense-hour-arc-shows-no-pending-entries`).
- **D4.** The history page's "Last 30 days" summary card (1d leftover). History page. S.
- **D5.** DONE (#145, merged 2026-11-08; the leftovers below are follow-ups). The rest of 1g: rebuild `integration_test/` around the fan gestures, dial semantics and sheets, on iOS and
  `E2E_DEVICE=macos` (#119 did the finders and the one-build suite). #145 (`feat/e2e-1g-mac-window`):
  `log_fan_test.dart` (press-drag-release onto a wedge, a release off the fan, Escape, Log's screen-reader actions, a
  wedge's tap and hold through semantics), and the Trends helpers and checks follow the sheet or the split pane.
  Left: the amount sheet's tests wait on D1; the macOS run of the suite on the split view is unproven until D6 or a
  hand run of `E2E_DEVICE=macos tools/e2e.sh`. `integration_test/`. M.
- **D6.** Run the macOS e2e suite in CI after merge, beside iOS (`e2e.yml` runs iOS only; C10 puts e2e in CI and
  `r2-mac` ships the Mac only if its e2e is green). `.github/workflows/e2e.yml`. M.
- **D7.** DONE (#145, merged 2026-11-08; #108 closed). #108 (`r8-mac-window` B, 1200 x 780): carried onto #145 (with D5) without its 800 x 600 test override;
  close #108 when #145 merges. `macos/Runner/MainFlutterWindow.swift`. S.
- **D8.** Queue item 6, widgets, Control Centre controls and the Mac menu bar app. First check that the free signing
  team can sign App Groups and app extensions (if not, it moves to BLOCKED with B2), then build. New native targets. L.
- **D9.** `flutter build macos --release` fails on this machine at Flutter's architecture check; workaround: xcodebuild
  with `ARCHS=arm64`. Likely cause (inferred, unverified): the machine's Homebrew Flutter is 3.44.7, and the release
  build needs 3.44.8 or later (flutter/flutter#188346); CI's pin is 3.44.9. Move the machine to 3.44.9 while no agent
  is building, and rebuild. Machine setup. S.
- **D10.** DONE (#136, merged 2026-11-08). `flags=$(tools/build-version.sh) && flutter build ipa $flags` passes the flags as one word in zsh.
  `CLAUDE.md` already notes `${=flags}`; make the tool shell-safe (for example, it runs the build command it is given).
  `tools/build-version.sh`, `CLAUDE.md`. S.
- **D11.** Flutter 3.47 (Dart 3.13) and riverpod_lint 3.1.9, the separate step `CLAUDE.md` records.
  `.github/actions/setup-flutter/action.yml`, `analysis_options.yaml`. M.
- **D12.** DONE (#139, merged 2026-11-08; the rules-and-indexes entry stays: console drift and the unused `archived` index are still unchecked). Close the register entries that recorded a call Jack has since made, or that no longer hold:
  `activity-timestamps-come-from-the-device-clock` (`r4-server-time`: as built), `vice-lists-are-unbounded`
  (`r4-vice-cap`: no cap for 1.0), `no-email-verification` (`r3-verify`), `every-firebase-command-targets-production`
  (the CLI's configstore no longer maps the checkout, checked 2026-11-08; `r2-testflight`: no beta project). Re-check
  `rules-and-indexes-are-never-deployed-or-tested` (CI deploys; #90 checks the index file against the queries).
  `tech-debt/`. S.
- **D13.** The rest of the register, one class per PR: the generated plugin registrant tracked on macOS only
  (medium), the duplicated client API key, the template tests, the e2e record helper flake (low). `tech-debt/`. S each.
- **D14.** DONE (#139, merged 2026-11-08). Refresh `ideas/`: its "Needs Jack" section asks calls Jack has made (E2EE, age, Mac, Pro, billing,
  TestFlight, icon, guests, check-in, presets, triggers, Today, app lock), and idea files for shipped work remain
  (`end-to-end-encryption`, `one-tap-quick-logging`, `trigger-tagging`, `granular-logging-and-data-model`, part of
  `guest-mode-and-sign-in`): delete or trim each. `ideas/`. S. The deleted E2EE file's open items moved to
  `tech-debt/firebase-data-layer/` (sealed-only rules, binding scope and key rotation, migrator edge cases),
  `tech-debt/auth-and-account-lifecycle/` (clipboard), the release-pipeline idea (export compliance) and the privacy
  idea (Crashlytics scrubbing).
- **D15.** Close draft #128 (the keychain probe, CONFLICTING, "not for merge") once P2 no longer needs it. S.
- **D16.** Reduce motion row in Settings (`r10-reduce-motion` B, Jack, 2026-11-08): Follow system / Reduce / Full, saved
  per device in `shared_preferences`. PR #153 (`feat/reduce-motion-setting`). Full cannot bring back motion the
  framework scales itself: while iOS Reduce Motion is on, every default `AnimationController` runs at 5% of its length
  and no release-mode API turns that off. So Full covers the app's own controllers (`AnimationBehavior.preserve`: dial,
  log fan, tallies, day picker, Undo timer, status pills (`PillDrop`), the Trends range morph (`RangeMorph`)) and pushed
  pages (`DialPageRoute`); sheets, dialogs and implicit animations (segment thumbs, label fades) still follow the
  system, and the page's foot copy says so. Open: a custom `WidgetsFlutterBinding` overriding
  `SemanticsBinding.disableAnimations` would cover the rest (inferred, untested).

**Were UNDECIDED; all decided in round 10 (2026-11-08)** (U1 to U8; see Jack's calls, round 10, below):

- **U1.** DECIDED (`r10-mac-fullscreen` B, responsive scaling). Mac fullscreen layout: one of P3's three options.
  Build M from `design/mac-fullscreen-b` (the tag
  `archive/design/mac-fullscreen-b` once archived), with the pitch's two conditions: cap the dial near 480 pt, and keep
  Today's column at 504 pt at 1200 x 780 (Claude's conditions, in the pitch's recommendation; Jack picked B as
  presented).
- **U2.** DECIDED (`r10-widget-top` D, `r10-widget-undo` B, `r10-intents` A, `r10-mac-widgets` A; queue item 6 holds
  them). Queue item 6's open questions: what "top" habits means, Undo after a widget or menu bar tap, Siri, Shortcuts
  and the Action button through the same App Intent, macOS desktop widgets from the same code.
- **U3.** DECIDED (`r10-reduce-motion` B; in progress as PR #153, `feat/reduce-motion-setting`). A Reduce motion row in Settings, as the mock-up has; the app follows the
  system setting and has nothing of its own to set. S.
- **U4.** DECIDED (`r10-languages` A): English only. Other languages (register: English only). No work.
- **U5.** DECIDED (`r10-analytics` A): none. Analytics beyond Crashlytics, content-free
  (`ideas/v1-must-haves/crash-reporting-and-analytics.md`), which the idea defers to 1.1. No work.
- **U6.** DECIDED (`r10-reminders` B): one optional daily nudge. Reminders: `r2-days` ruled out the daily check-in,
  not reminders (`ideas/v1-must-haves/evening-check-in-and-reminders.md`). M.
- **U7.** DECIDED (`r10-pitch-branches` C). The Day Dial files landed in the PR from `docs/round-10-picks`; the
  archive tags and branch deletions are for the main session after it merges. The pushed pitch-source branches with
  no PR (`mockup/*`, `design/ui-overhaul-*`, `design/mac-fullscreen-*`, `spike/*`): land the picked Day Dial mock-up
  (`index.html`, `notes.md`, `tokens.json`, the stills) on `master`, tag each other branch `archive/<branch>`, then
  delete the branches. S.
- **U8.** DECIDED (`r10-release` B): wait. Cut 0.2.0 once the picked Mac fullscreen layout and PR #133 (AutoFill)
  land. When to cut 0.2.0 and install it on Jack's iPhone and Mac (the iPhone runs 0.1.0). Its first launch runs the
  sealing migrator over his real journal. S.

**BLOCKED on Jack** (tasks, not decisions):

- **B1.** Read `dailyOrphanCleanup`'s "Orphan cleanup would delete" logs for a few days (deployed 2026-11-07; first
  run 04:30 UTC 2026-11-08). Claude can't read production logs. Then Claude pitches the one-line flip of
  `DELETE_ORPHANED_DATA`. S.
- **B2.** The paid Apple Developer team, which Jack is not getting for now: App Attest, App Check registration and
  enforcement, TestFlight, Sign in with Apple, the App Store.
- **B3.** Waits on a release: the domain, the support and legal pages, the privacy-policy details, an App Store search.
- **B4.** The main checkout's modified `macos/Runner.xcodeproj/project.pbxproj`: discard or keep.
- **B5.** Delete the old `com.screendead.tracker.tracker` install, then its two iOS registrations in the console.
- **B6.** Optional: Cloud Scheduler's "Force run" on the monthly summaries job, to fill them before the 1st.

**CI on `master`:** the last finished e2e run is green (a2b5c30, #130); the run for 82f69f0 (#132, #134) was still
going at the time of writing. The one red run, fef30f9 (#116, 2026-11-07), was followed by green runs. The Dependabot
failures of 2026-11-07 (functions' minimatch and glob) predate #120, and no alerts are open. Skipped tests: the
fidelity renders (they skip without an output directory) and the DST guards (they skip in a zone without DST; CI sets
`TZ=Europe/London`). None is skipped by mistake.

### This run (`/finish-and-pitch`, second pass, started 2026-11-06)

Closed: every track below is merged (2026-11-06/07). The first pass (waves A to D) is merged. CI was down on 2026-11-06 (Actions billing limit) until Jack made the repo
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

**UNDECIDED:** none on the pitch page: round 9 is picked (2026-11-07), as is every earlier call (2026-11-06). `r7-ci`
and round 5 are moot and off the page. Other languages are still unasked.

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
  (https://claude.ai/artifact/JGnHCcPxaTLHKiyZeFgNmK, sources on the tag `archive/mockup/icon-sheet`). Shipped as the iOS and macOS
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
  document per user, to cut reads and load times, especially for the graph and calendar. How it runs: **a Cloud
  Function** (Jack, 2026-11-06, over the app refreshing the document itself). Amounts and times stay unsealed under
  `r2-e2ee` for this; names and units are sealed, so the function reads `viceID` and `quantity` only. Built in the PR
  from `feat/bead-summary-function`.
- **`r8-tally-target`**: **44 x 38, as built.** No work.
- **`r8-mac-window`**: **about 1200 x 780, the split view by default**; lands with 1g.
- **`r8-mac-keys`**: **Cmd-1 to Cmd-9 log one of the Nth habit now**, listed in the menu bar. Queued.

## Jack's calls, round 9 (2026-11-07)

Picked on the pitch page, each as recommended:

- **`r9-archive`**: A, **the archive button on the habit's history page, as built.** No work.
- **`r9-appearance`**: B, **a Match system / Light / Dark choice, saved on the device** with shared_preferences
  (each device keeps its own; no data-model or rules change). Built in the PR from `feat/r9-picks`.
- **`r9-export`**: B, **also an Export row in Settings, as the mock-up**; Account Settings keeps its row beside
  Delete, and both share one export action. Built in the PR from `feat/r9-picks`.

## Jack's calls, round 10 (2026-11-08)

Picked on the round 10 pitch page (`docs/pitch/round-10/`). Ten match Claude's recommendation; `r10-mac-widgets`
does not (Claude recommended B, later). Notes are Jack's.

- **`r10-mac-fullscreen`**: B, **responsive scaling.** Both panes grow with the window; the dial scales with the
  height. Built from `design/mac-fullscreen-b` (U1).
- **`r10-widget-top`**: D, **the top habits are the most logged in the last 30 days, overridable by hand in the
  widget's settings.**
- **`r10-widget-undo`**: B, **a 5-second Undo where you tapped.**
- **`r10-intents`**: A, **Siri, Shortcuts and the Action button through the same log intent**, built with the widgets.
- **`r10-mac-widgets`**: A, **macOS widgets from the same code**, built with the iPhone widgets. Jack: "Widgets for the Notification Centre are useful to me."
- **`r10-reduce-motion`**: B, **a Follow system / Reduce / Full row in Settings, saved per device** like Appearance.
- **`r10-languages`**: A, **English only.**
- **`r10-analytics`**: A, **none** beyond Crashlytics.
- **`r10-reminders`**: B, **one optional daily nudge**, off by default. Jack: long-pressing the notification should
  offer something like "Nothing further" or "Clean day"; it needn't do anything, but should feel good to press.
- **`r10-pitch-branches`**: C, **land the Day Dial mock-up files, tag the rest as `archive/*`, then delete those
  branches.** The files are in `docs/pitch/mockups/ui-overhaul/day-dial/`; the tag and delete commands are in the PR
  from `docs/round-10-picks`, for the main session to run after it merges.
- **`r10-release`**: B, **wait** for the Mac fullscreen layout and AutoFill (#133) before cutting 0.2.0.

Later the same day, in chat, on the widgets (#158) and the nudge (#156):

- **Background refresh, battery-light.** Jack: "Background refresh now. Don't use up all of my phone's battery with
  it." A log from a widget, control or Siri reaches Firestore without opening the app: on iOS a `BGAppRefreshTask`
  asked for only while logs are queued, timed by the system; on the Mac, while the app runs, a retry every 15
  minutes or more at utility priority, only while logs are queued. No polling, no silent push. Built in #158.
- **Habit names and counts in the App Group, plaintext on the device, are acceptable.** The widgets' snapshot and
  queue stay as built in #158 (they clear on sign-out).
- **The Lock Screen shows the top 3.** As built in #158.
- **The daily nudge fires every day regardless**, even on a day already logged. Jack: "in case something was
  missed". As built in #156; no change.
- **"Clean day" just dismisses** (option c). As built in #156; no change.

## Calls waiting on Jack (UNDECIDED)

None. U1 to U8 in the overnight list (under the queue) were decided in round 10 (Jack's calls, round 10, above).

Round 5 (`r5-radar-inset`, `r5-key-height`, `r5-key-always`) is moot: the radar and its key left Today in #83.

## For Jack to do (not decisions)

- **Orphaned guest data cleanup runs as a dry run** (`dailyOrphanCleanup` in `functions/index.js`, 04:30 UTC;
  deployed 2026-11-07, overnight list B1). It
  logs "Orphan cleanup would delete" with each uid and its document counts once two runs a day apart find the
  account gone. After a few days of those logs look right, deleting is the one-line change
  `DELETE_ORPHANED_DATA = true`, in its own PR.
- **Turn on the monthly summaries function: done.** `DEPLOY_FUNCTIONS` is `true` and the 2026-11-07 deploy updated
  `monthlySummaries`; only the optional "Force run" (B6) is left. The steps, for the record: In order: (1) move `screendead-vice-tracker` to the Blaze plan; (2) enable the Cloud Functions, Cloud
  Build, Artifact Registry, Cloud Scheduler, Cloud Run, Eventarc and Pub/Sub APIs; (3) grant the deploy service
  account (now Firebase Rules Admin, Cloud Datastore Index Admin, Service Usage Consumer) Cloud Functions Admin
  (`roles/cloudfunctions.admin`) and Service Account User (`roles/iam.serviceAccountUser`) on the default compute
  service account, plus Cloud Scheduler Admin (`roles/cloudscheduler.admin`) and Artifact Registry Administrator
  (`roles/artifactregistry.admin`, for the CLI's image cleanup policy; or run
  `firebase functions:artifacts:setpolicy` once yourself); (4) set the repository variable `DEPLOY_FUNCTIONS=true`;
  (5) re-run the Cloud Functions workflow on `master`. The first deploy names any permission still missing. The
  function's runtime account (the default compute service account) needs Firestore read and write
  (`roles/datastore.user`), which it holds unless it was trimmed. To fill the summaries at once rather than on the
  1st, use Cloud Scheduler's "Force run" on the job.

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
- `GeneratedPluginRegistrant` is gitignored on both platforms; `flutter pub get` and every flutter build regenerate it.
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
