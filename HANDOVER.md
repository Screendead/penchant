# Handover — Tracker

*Updated 2026-11-08 (insights queue). Audience: the next agent, or Jack. The current task; `CLAUDE.md` says what this
file holds and how to keep it.*

## The goal

A production-quality habit journal for Jack's own use (`r2-privacy`, Jack, 2026-11-06): "I'm not actually going to
put it on the App Store; it's just for me." Build it with release polish; the store, legal and payment work waits
until and unless he decides to sell, and what needs a paid Apple team or a release waits too (For Jack to do). The
order stays: make what exists work, keep it safe to change, burn down the debt, then build the journal and insights
from `ideas/`.

## "Do the next thing"

Take the **top unblocked item in the queue below**, do it end to end (branch, PR, merge, with whatever pre-merge
testing the e2e rule in `CLAUDE.md` asks for), tick it off here in the same PR, and stop. Work the queue top down; if
an item is blocked on Jack, skip to the next one and say so. Items under one number can run in parallel in separate
worktrees. `/finish-and-pitch` works through the whole queue: its DECIDED list is the queue, its UNDECIDED list is
"Calls waiting on Jack".

## Where things stand

| Item | State | Where |
|---|---|---|
| Standing rules, CI checks, emulator and iOS e2e harness | Merged 2026-11-02 (#24, #25, #29) | `CLAUDE.md`, `.github/workflows/`, `tools/e2e.sh` |
| Firestore rules rewrite (#27) | Deployed to production by Jack 2026-11-03 | `firestore.rules` |
| Recovered features and the fixes for Jack's two reported bugs (#28) | Merged and live 2026-11-03 | `lib/` |
| Jack's round-1 calls C1–C19 | Picked 2026-11-03; built in wave 3 | below |
| Wave 3: Today and recording C2–C5 (#36), rules details C12–C14 (#33), platform and repo cleanup C1 C6–C11 (#34), ideas rework C15–C19 (#35) | Merged 2026-11-03; #33's rules reached production through CI on 2026-11-04 | `lib/`, `firestore.rules`, `.github/workflows/deploy-firestore.yml`, `ideas/` |
| Wave A of the finish-and-pitch run: Dependabot #37 #38, seed script emulator-only (#44), parsers default every field (#45), shared write layer `TrackerWrites` (#46), versioning 0.1.0 + changelog + release workflow (#43) | Merged 2026-11-03 | `lib/`, `admin/`, `CHANGELOG.md`, `.github/workflows/release.yml` |
| Security patch: cloud_firestore 6.10.2, Firebase iOS SDK 12.19.3, for Firebase's eMudhra CA notice (#56) | Merged 2026-11-03; Jack's iPhone got release 0.1.0 (244) built from it, and both platforms have since been installed as build 964 (queue item 6) | `pubspec.yaml`, `ios/Podfile.lock` |
| Wave B: rules-test deps (#49), accessibility (#51), navigation (#52), offline logging (#53), backend hardening with App Check client wiring (#55), account export, deletion, password reset and verification behind `accountProvider` (#54); register additions (#57); round-3 calls on the pitch page (#58) | Merged 2026-11-03/04. The new activities index is deployed to production (by Claude, with Jack's leave, 2026-11-03). App Check state: `CLAUDE.md` | `lib/`, `integration_test/`, `firestore.indexes.json` |
| Wave C: register additions refreshed (#60), refused offline writes surface in a banner and Manage Data counts offline (#61), startup and load errors show a message with Retry (#62), dead lint and codegen tooling removed with riverpod_lint running in CI through `dart analyze` (#63), the record dialog's vice dropdown keyed on the id (#65, an e2e flake) | Merged 2026-11-04 | `lib/`, `.github/workflows/checks.yml` |
| Wave D: data layer (#68), repo hygiene (#70), usage graph (#69), locale formatting (#67), widget state (#71), dead code and a `dart format` CI step (#66), Today chart keeps vice names readable at large text (#74), admin glob override for Dependabot alerts 197/198 (#75), pitch round 4 (#73) | Merged 2026-11-04. Each ran the full iOS e2e (31 tests) before merge, except #73 (docs) and #75 (seed script only; ran it under the emulators) | `lib/`, `admin/`, `docs/pitch/` |
| CI deploys rules and indexes | On since 2026-11-04 (run 41822697732 first; #71's merge deployed too); the rule is in `CLAUDE.md` | `.github/workflows/deploy-firestore.yml` |
| Web site | Down (`r2-web-site`) | |
| macOS target (#47) | Merged 2026-11-05: `E2E_DEVICE=macos tools/e2e.sh` passes 31/31 (15 files, one `flutter test` each) beside iOS 31/31 | `macos/`, `.github/workflows/macos-build.yml` |
| UI overhaul: Day Dial (`r6-ui-direction`, Jack 2026-11-05) | 1a to 1e merged: 1a #79, 1b #83 with the fidelity pass #94, 1c #89, 1d #100, 1e #99 (2026-11-05/06). 1f partly (#98) and 1g partly (#119); what is left is in the overnight list (D1 to D5) | `lib/design/`, `assets/fonts/`, `lib/widgets/day_dial.dart` |
| Rounds 2–4, 8 and 9 on the pitch page | All picked; status under "Calls waiting on Jack" | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Brand: Penchant (`r2-brand`) and "habit" wording | Strings in #81 (2026-11-05). Bundle ID `com.screendead.penchant` done (#84, 2026-11-06); both development profiles exist, and a signed `flutter build ios --release` carries the new ID | `lib/firebase_options.dart`, `ios/`, `macos/` |
| End-to-end encryption (`r2-e2ee`, `r2-e2ee-key`) | On: merged in #130 (2026-11-08), after the crypto core (#115), sealed fields (#117), the migrator (#114), the key UI (#116) and the key service (#124); the post-merge e2e run on a2b5c30 passed. Open follow-ups: the sealed-only rules, sealed-blob binding and migrator edge cases (`tech-debt/firebase-data-layer/`), the recovery-key clipboard (`tech-debt/auth-and-account-lifecycle/`), export compliance (release-pipeline idea), Crashlytics scrubbing (privacy idea). Key sync from iPhone to Mac: P2 | `lib/crypto/` |
| Tech-debt register | Counts in `tech-debt/README.md` (from `tools/tech-debt-recount.py`); 162 issues on 2026-08-11 | `tech-debt/README.md` |
| Product backlog | Counts in `ideas/README.md` | `ideas/README.md` |
| Cloud Functions | Deployed by CI (below) | `functions/`, `.github/workflows/functions.yml` |

Cloud Functions deploy through CI: `functions.yml` runs `npm --prefix functions test` on PRs touching `functions/`,
`firebase.json` or itself and, on such a push to `master`, deploys (`firebase deploy --only functions`, pinned
firebase-tools, `firestore-production` environment) while `DEPLOY_FUNCTIONS` is `true`. Jack set it `true` on
2026-11-07; run 42410165620 created `dailyOrphanCleanup` (a dry run; For Jack to do) and updated `monthlySummaries`.
Only the optional Cloud Scheduler "Force run" of the monthly summaries job is left (B6).

CI and the post-merge e2e run are described in `CLAUDE.md`; why `flutter build macos --release` fails on this machine
is D9.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's calls below. Subagents write PR bodies to uniquely
named scratchpad files: the scratchpad is shared, and a generic `pr-body.md` once put one PR's description on another.

1. **The Day Dial UI overhaul** (`r6-ui-direction`, below), from the mock-up and its Flutter notes (`CLAUDE.md`,
   design). One PR per step, in order; every screen keeps working between steps, and each PR keeps `tools/e2e.sh` green
   by updating the tests its screens break. Status 2026-11-08: 1a to 1e are merged, 1f and 1g partly; what is left is
   D1 to D5 in the overnight list. The step notes below are history.
   - **a. Theme foundation** (#79): tokens, light and dark `ThemeData` (the mode is now `r9-appearance`'s choice),
     bundled fonts, the habit colour function, the hard-coded colours replaced.
   - **b. Today** (#83): the dial (`CustomPainter`, beads at their times, now-hand, clear-day ring), the tally rows with
     a `+` each, the one-tap "log one" action (the layout-neutral half of one-tap logging), the Log button and its fan,
     the amount sheet that replaces the record dialog for new entries, and the calendar sheet. #83 shipped all but the
     amount sheet: a held wedge (or More, past eight habits) opened the record dialog with the habit chosen, until D1
     (#148). Left then: the amount sheet (D1, with 1d's editor, which reuses it), the SyncBadge pill (built in #94),
     merging a dense hour's beads into one arc above about 48 entries (D3), docking the Log button on the Trends sheet
     (done in 1c). The offline banner and the day's pending note stay. Bead size was against the habit's median entry
     on the shown day, so it cost no extra read; "your usual" ghost beads and a cross-day typical would cost a 7-day
     query; `r8-bead-size` replaced both (item 4).
     Fidelity pass (#94, `feat/today-fidelity`), after Jack found Today unlike the mock-up: the Penchant wordmark menu
     (Habits, Settings, sync footer) replaces the drawer, the Synced pill is built on `waitForPendingWrites`
     (`syncStatusProvider`), the mock-up's spacing fits five tallies above the Log button on a 390 x 844 phone, light
     shadows, stroke icons, dimmed zero pips. Side by side in `docs/pitch/mockups/ui-overhaul/day-dial/fidelity/`;
     re-render with `tools/fidelity/`. Still different, by the 3:1 floor: the clear day's major spokes, pip and wedge
     rims, the sparkline's daily line. Jack's round 8: no coach pill, the clear day's majors at 25%, bead size against
     a stored typical (`r8-bead-size`).
   - **c. Trends sheet** (#89, `feat/trends-sheet`, stacked on #83): the sheet over Today that replaces the Graph tab,
     with habit chips, range and Day/Week segments, the average stepper, stats, "when it happens", a day point opening
     its dial, and the Log button docked on its edge; weeks per `r4-weekly` B (item 4). Left for 1f (D2): the chart's
     morph between ranges (fl_chart tweens only equal-length series, so a range change snaps) and the day's container
     transform with the `animations` package (it fades in place).
   - **d. Habits, history and the entry editor** (#100, `feat/overhaul-1d-habits`): Manage Data becomes Habits; Habits
     and the history page in the card style; swipe-to-delete with Undo on history rows and Undo on the editor's delete
     (the register's inconsistent-delete item is gone); Archive and Edit habit moved to the history page; editing
     reuses the amount sheet. Left: the amount sheet (D1; the editor kept its form), the history page's "Last 30 days"
     summary card (D4), page transitions (1f, D2).
   - **e. Auth and settings screens** (#99, `feat/overhaul-1e-account`): one sign-in screen with a segmented control and
     the password checklist; Settings and Account Settings in the card style; copy as written (`r3-delete-copy`); the
     3:1 keyboard focus ring on card rows, the sign-in segments and the slider (a 2 pt accent ring in place of
     Material's 12% overlay); the unused navigation-bar themes gone with the sign-in BottomNavigationBar. Left: the
     Habits and history `ListTile`s (1d's files) still show only Material's overlay. Side by side in `fidelity/signin-*`,
     `signup-*`, `settings-*` (`test/fidelity_account_render_test.dart`).
   - **f. Motion polish:** bead travel, day sweep, springs, page transitions (the mock-up's notes add the `animations`
     package), and the reduce-motion fades.
   - **g. e2e rewrite:** rebuild `integration_test/` around the new flows (fan gestures, dial semantics, the sheets), on
     iOS and `E2E_DEVICE=macos`.
2. **The macOS split view: done** (#92, merged 2026-11-06, `feat/macos-split-view`; from `notes.md`, "macOS"; how it
   works is in `CLAUDE.md`). The Mac runs the e2e suite on the split view, iOS on the sheet.
3. **Bundle IDs to `com.screendead.penchant`: done** (#84, merged 2026-11-06): Runner and RunnerTests on both platforms,
   the Penchant `GoogleService-Info.plist` on both, `firebase_options.dart`, the macOS keychain group. The idea file is
   deleted; its leftovers (the domain variant, an App Store search on a device) moved to the support-pages and
   TestFlight ideas and to For Jack to do. iOS e2e 31/31 and a signed release build pass, and the review's full
   `E2E_DEVICE=macos tools/e2e.sh` (2026-11-06, load about 7) passed 31/31 with 34 registrations. Earlier runs under
   load 40 and up had 3 of 70 registrations time out at 30 s (Homepage never appeared), beside other 30 s timeouts that
   touch no Auth code (a server count, a dialog close); a load effect, not a keychain one, is the likelier reading. If
   the hang comes back on a quiet machine, the macOS keychain access group (`macos/Runner/*.entitlements`) is the one
   ID-specific piece on Auth's persistence path.
4. **The work from the 2026-11-06 picks** (rounds 2 to 4 and 8, below): `r8-clear-spokes` B, `r4-weekly` B (deletes
   the register's oldest-weekly-bucket item), `r8-mac-keys` B, `r8-mac-window` B, Crashlytics (`r2-crash` A), guest
   start with linking an email later (`r2-signin`, the part that needs no paid Apple team), onboarding (`r2-presets`
   A), the data model (`r2-data-model` B), trigger tagging (`r2-triggers` A), and end-to-end encryption (`r2-e2ee` A,
   `r2-e2ee-key` A). Status 2026-11-08: all built and merged (#103 to #107, #109 to #118, #124, #130; `r8-mac-window`
   in #145, D7). `r8-bead-size`'s monthly summary is built (PR from `feat/bead-summary-function`), and the dial sizes
   beads against its typicals. Sign in with Apple waits on the paid team (For Jack to do).
5. **The rest of the register**, medium then low, one class per PR.
6. **Soon: iPhone widgets, Control Centre controls and a Mac menu bar app** (Jack, 2026-11-07). Build all of these:
   - **Home and Lock Screen widgets** in every size WidgetKit offers (small, medium, large, extra large on iPad, and
     the Lock Screen's circular, rectangular and inline). One kind shows **last week's usage of every habit**; the
     other **records one usage of one of the top 1, 3 or 8 habits** (the size picks how many).
   - **Control Centre controls** (iOS 18 `ControlWidget`), one button that logs one usage of a chosen habit.
   - **A macOS menu bar app**: the dial at the top and the habits listed below it. Clicking a habit logs one usage
     at the current date and time.

   Constraints: these are native Swift targets (WidgetKit, App Intents) because Flutter does not run in an extension.
   Habit names are sealed, so showing them needs the app's Firebase Auth session and the E2EE key through a shared
   Keychain access group and an App Group. The free signing team can sign App Groups and app extensions on iOS (proven
   2026-11-08 on `spike/widget-app-group`, commit becdcaf: WidgetKit extension `com.screendead.penchant.widgets` and
   App Group `group.com.screendead.penchant`, the app wrote to the group and the widget read it on Jack's iPhone;
   `tools/add-widget-target.rb` there generates the target); macOS App Groups are available to free teams per Apple's
   docs, but whether sandboxed macOS needs a TEAMID-prefixed group name is unchecked. Read Apple's current WidgetKit,
   App Intents and ControlWidget docs first. Jack's round 10 picks settle the open questions (`r10-widget-top` D,
   `r10-widget-undo` B, `r10-intents` A, `r10-mac-widgets` A; Jack's calls, round 10, below); whether WidgetKit can
   hold and revert the Undo state is unchecked. The idea file is
   [widgets-and-shortcuts](ideas/growth-later/widgets-and-shortcuts.md).
   Status 2026-11-08: after Jack's call (2026-11-08: "the menu bar app should still be present even when the app is
   cmd+q'd too"; "do it properly"), the Mac menu bar is a native login-item helper (`macos/PenchantMenuBar`, a SwiftUI
   `MenuBarExtra` embedded at `Contents/Library/LoginItems`, registered with `SMAppService.loginItem` at each app
   launch). It reads the widgets' App Group snapshot and queues logs in their `LogQueue`; the app writes them, sealed,
   on its next flush. With the app closed, the helper launches it hidden (no window or Dock icon) to flush and quit
   (`FlushMode`, PR #167). The run leaves its outcome in the App Group; the helper retries a `retry` when the network
   returns, on wake and on a backoff of about an hour, and says "open Penchant to sync" for a `blocked` one. The
   in-process popover (#157, #163) is gone, and with it the private `enableMultiView` call, which also sent VoiceOver to
   the wrong view (`FlutterEngine.mm`, `update_semantics_callback2`).
   On iOS the log intents are `LiveActivityIntent`s (PR #166), so iOS runs a widget, control, Siri or Shortcuts log in
   Penchant's process, launched in the background if need be; it flushes once the Undo hold passes, under a
   background task, with `BGAppRefreshTask` kept as the fallback. Jack's "do it properly" (2026-11-08) settled
   `r11-ios-widget-sync` as B. Both platforms installed as build 964; neither path proven on a device yet.

7. **Insights, built free** (Jack, 2026-11-08: "build it free for me, we can paywall later"). The Pro features
   ship unlocked; the paywall and StoreKit wait until he decides to sell. Apple Health works on the free team: a
   signed probe build on 2026-11-08 got a profile granting `com.apple.developer.healthkit` and background delivery.
   Small, resumable steps, one PR each, merged on green; tick each here as it merges. Health and every source below
   stay on the device: nothing they read goes to Firestore, analytics or crash reports.
   - **a. Engine core** (pure Dart, `lib/insights/`): per-day series from the decrypted journal, a "what follows"
     comparison of an outcome on days after each habit against days without, attributed per habit, and a refusal to
     report below a minimum sample or inside the noise (`ideas/insights/insights-engine.md`).
   - **b. Health reading** (iOS Swift channel): the entitlement, usage string, permission asked from the Insights
     screen only, daily and nightly aggregates (`HKStatisticsCollectionQuery`) for sleep stages, HRV, resting heart
     rate, respiratory rate, oxygen, wrist temperature, steps and energy, kept in an on-device store
     (`ideas/insights/apple-health-correlation.md`, recommendation B with C's aggregates).
   - **c. Insights screen:** connect Health, then show the engine's findings; empty Health reads as "no data yet".
   - **d. Health history backfill and incremental sync** (anchored queries, then background delivery).
   - **e. Calendar** (`ideas/insights/calendar-integration.md`). **f. Weekly review**, then **g. trend overlays**.
   - **h. More sources** (Jack, 2026-11-08: "add them all to the roadmap";
     `ideas/insights/more-data-sources.md`): Health beyond sleep and heart rate, places, daylight, music, Reminders
     and Focus first; Journaling Suggestions, weather, Screen Time and spending carry the blockers in that file.

### Overnight run (`/finish-and-pitch`, 2026-11-08)

The inventory of open work as of 2026-11-08, from `origin/master` at 82f69f0, the open PRs, the remote branches, CI on
`master`, the register and the backlog. Effort: S under a day, M a day or two, L more.

**In progress, owned by other agents (leave alone):**

- **P1.** DONE (#133, merged 2026-11-08). Native AppKit auth fields on macOS for Passwords AutoFill, made less clunky
  (`feat/mac-native-auth-fields`).
- **P2.** Why the journal key did not sync from iPhone to Mac through iCloud Keychain: being investigated on
  `fix/journal-key-sync` (not on `origin` yet at the inventory).
- **P3.** Mac fullscreen layout pitch, 3 options. `design/mac-fullscreen-a` is pushed; b and c are local worktrees.

**DECIDED** (the goal is set by a recorded call or a convention):

- **D1.** DONE (#148, merged 2026-11-08): the amount sheet (title, stepper, pill button) replaces the record dialog
  for new entries, and the editor page builds the same `AmountFields` (1b and 1d leftover). Follow-ups: the mini dial
  for the time, which replaces `ActivityDateField` in the mock-up (next; D2's edited bead travel needs it); the step
  of 5 for habits whose typical entry is 10 or more; the editor as the sheet itself rather than a page (with D5, which
  rewrites the editor e2e flows). `lib/widgets/`. M.
- **D2.** The rest of 1f, as #98's "Left for 1f" lists it: `animations` page transitions, `OpenContainer` for a
  Trends day point, the chart morph between ranges, the offline and refused-write pills on a spring, an edited bead
  travelling to its new time (needs D1), the reduce-motion day fade, the dial's drag snap-back. `lib/widgets/`. L.
- **D3.** DONE (#146 from `feat/dense-hour-arc`, merged 2026-11-08; stills in `docs/pitch/dense-hour/`; 1b leftover).
  Above 48 entries in a day, an hour with more than one entry is one arc; an hour's lone entry stays a bead, pushed
  clear of the arcs. The arc draws no pending rim for unsynced entries in it (register,
  `dense-hour-arc-shows-no-pending-entries`). `lib/widgets/day_dial.dart`. S.
- **D4.** The history page's "Last 30 days" summary card (1d leftover). History page. S.
- **D5.** DONE (#145 from `feat/e2e-1g-mac-window`, merged 2026-11-08). The rest of 1g: `integration_test/` rebuilt
  around the fan gestures, dial semantics and sheets, on iOS and `E2E_DEVICE=macos` (#119 did the finders and the
  one-build suite): `log_fan_test.dart` (press-drag-release onto a wedge, a release off the fan, Escape, Log's
  screen-reader actions, a wedge's tap and hold through semantics), and the Trends helpers and checks follow the sheet
  or the split pane. Follow-ups: the amount sheet's tests wait on D1; the macOS run of the suite on the split view is
  unproven until D6 or a hand run of `E2E_DEVICE=macos tools/e2e.sh`. `integration_test/`. M.
- **D6.** Run the macOS e2e suite in CI after merge, beside iOS (`e2e.yml` runs iOS only; C10 puts e2e in CI and
  `r2-mac` ships the Mac only if its e2e is green). `.github/workflows/e2e.yml`. M.
- **D7.** DONE (#145, merged 2026-11-08; #108 closed). #108 (`r8-mac-window` B, 1200 x 780) was carried onto #145
  without its 800 x 600 test override. `macos/Runner/MainFlutterWindow.swift`. S.
- **D8.** Queue item 6, widgets, Control Centre controls and the Mac menu bar app; the signing check is done (queue
  item 6: proven on iOS; macOS App Group naming unchecked). New native targets. L.
- **D9.** `flutter build macos --release` (universal) fails on this machine at Flutter's architecture check;
  workaround: xcodebuild with `ARCHS=arm64`. The release build needs Flutter 3.44.8 or later under Xcode 27
  (flutter/flutter#188346, Xcode 27's `lipo`); CI's pin is 3.44.9 and last passed on 2026-11-05. That this machine's
  Homebrew Flutter, 3.44.7, is why it fails here is inferred, unverified. 3.44.9 sits at
  `~/development/tracker-tools/flutter-3.44.9`: move the machine to it while no agent is building, and rebuild.
  Machine setup. S.
- **D10.** DONE (#136, merged 2026-11-08): `tools/build-version.sh` runs the build command it is given (the `release`
  skill).
- **D11.** Flutter 3.47 (Dart 3.13) and riverpod_lint 3.1.9, the separate step `CLAUDE.md` records.
  `.github/actions/setup-flutter/action.yml`, `analysis_options.yaml`. M.
- **D12.** DONE (#139, merged 2026-11-08). Closed the register entries that recorded a call Jack has since made, or
  that no longer held: `activity-timestamps-come-from-the-device-clock` (`r4-server-time`: as built),
  `vice-lists-are-unbounded` (`r4-vice-cap`: no cap for 1.0), `no-email-verification` (`r3-verify`),
  `every-firebase-command-targets-production` (`r2-testflight`: no beta project). The rules-and-indexes entry
  (`rules-and-indexes-are-never-deployed-or-tested`, re-checked: CI deploys, #90 checks the index file) stays: console
  drift and the unused `archived` index are still unchecked. `tech-debt/`. S.
- **D13.** DONE (merged 2026-11-08), one class per PR: the generated plugin registrant tracked on macOS only (#137),
  the duplicated client API key (#138), the template tests (#140), the e2e record helper flake (#142). `tech-debt/`.
- **D14.** DONE (#139, merged 2026-11-08). `ideas/` refreshed: "Needs Jack" no longer asks the calls Jack has made
  (E2EE, age, Mac, Pro, billing, TestFlight, icon, guests, check-in, presets, triggers, Today, app lock), and the idea
  files for shipped work (`end-to-end-encryption`, `one-tap-quick-logging`, `trigger-tagging`,
  `granular-logging-and-data-model`, part of `guest-mode-and-sign-in`) are deleted or trimmed. The E2EE file's open
  items moved to `tech-debt/firebase-data-layer/` (sealed-only rules, binding scope and key rotation, migrator edge
  cases), `tech-debt/auth-and-account-lifecycle/` (clipboard), the release-pipeline idea (export compliance) and the
  privacy idea (Crashlytics scrubbing).
- **D15.** Close draft #128 (the keychain probe, CONFLICTING, "not for merge") once P2 no longer needs it. S.
- **D16.** Reduce motion row in Settings (`r10-reduce-motion` B, round 10): Follow system / Reduce / Full. PR #153
  (`feat/reduce-motion-setting`). Full cannot bring back motion the framework scales itself: while iOS Reduce Motion
  is on, every default `AnimationController` runs at 5% of its length and no release-mode API turns that off. So Full
  covers the app's own controllers (`AnimationBehavior.preserve`: dial, log fan, tallies, day picker, Undo timer,
  status pills (`PillDrop`), the Trends range morph (`RangeMorph`)) and pushed pages (`DialPageRoute`); sheets,
  dialogs and implicit animations (segment thumbs, label fades) still follow the system, and the page's foot copy says
  so. Open: a custom `WidgetsFlutterBinding` overriding `SemanticsBinding.disableAnimations` would cover the rest
  (inferred, untested).

**Were UNDECIDED; all decided in round 10 (2026-11-08)** (U1 to U8; the picks are in Jack's calls, round 10, below):

- **U1.** Mac fullscreen layout, one of P3's three options: `r10-mac-fullscreen` B. M.
- **U2.** Queue item 6's open questions (what "top" habits means, Undo after a widget or menu bar tap, Siri, Shortcuts
  and the Action button through the same App Intent, macOS desktop widgets from the same code): `r10-widget-top` D,
  `r10-widget-undo` B, `r10-intents` A, `r10-mac-widgets` A; queue item 6 holds them.
- **U3.** A Reduce motion row in Settings, as the mock-up has: `r10-reduce-motion` B (D16). S.
- **U4.** Other languages: `r10-languages` A, English only. No work.
- **U5.** Analytics beyond Crashlytics, content-free (`ideas/v1-must-haves/crash-reporting-and-analytics.md`, which
  defers it to 1.1): `r10-analytics` A, none. No work.
- **U6.** Reminders (`r2-days` ruled out the daily check-in, not reminders;
  `ideas/v1-must-haves/evening-check-in-and-reminders.md`): `r10-reminders` B, one optional daily nudge. M.
- **U7.** The pushed pitch-source branches with no PR: `r10-pitch-branches` C. The Day Dial files landed in the PR
  from `docs/round-10-picks`; the archive tags and branch deletions are for the main session after it merges. S.
- **U8.** When to cut 0.2.0 and install it on Jack's iPhone and Mac: `r10-release` B, wait. S.

**BLOCKED on Jack** (tasks, not decisions; each is detailed under For Jack to do):

- **B1.** Read `dailyOrphanCleanup`'s dry-run logs for a few days, then Claude pitches the `DELETE_ORPHANED_DATA`
  flip. S.
- **B2.** The paid Apple Developer team, which Jack is not getting for now.
- **B3.** Waits on a release: the domain, the support and legal pages, the privacy-policy details, an App Store
  search.
- **B4.** The main checkout's modified `macos/Runner.xcodeproj/project.pbxproj`: discard or keep.
- **B5.** Delete the old `com.screendead.tracker.tracker` install, then its two iOS registrations in the console.
- **B6.** Optional: Cloud Scheduler's "Force run" on the monthly summaries job, to fill them before the 1st.

**CI on `master`:** the last finished e2e run is green (a2b5c30, #130); the run for 82f69f0 (#132, #134) was still
going at the time of writing. The one red run, fef30f9 (#116, 2026-11-07), was followed by green runs. The Dependabot
failures of 2026-11-07 (functions' minimatch and glob) predate #120, and no alerts are open. Skipped tests: the
fidelity renders (they skip without an output directory) and the DST guards (they skip in a zone without DST; CI sets
`TZ=Europe/London`). None is skipped by mistake.

### This run (`/finish-and-pitch`, second pass, started 2026-11-06)

Closed: every track below and the first pass (waves A to D) are merged (2026-11-06/07), #83 too. CI was down on
2026-11-06 (Actions billing limit) until Jack made the repo public and renamed it `Screendead/penchant` the same day.

**DECIDED** (in order; code PRs stacked, to merge once CI was back or Jack waived it):

- **Track A, the overhaul, stacked on #83:** 1c Trends sheet, then 2 macOS split view, then 1d Habits/history/editor
  (with the amount sheet, swipe-to-delete with Undo, which also settles the register's inconsistent-delete item),
  1e auth and settings (with keyboard focus on list rows, navigation destinations and the slider, which #82 found at
  about 1.2:1), 1f motion polish, 1g e2e rewrite. One PR each, on top of the last.
- **Track B, Apple platform debt, off `master`:** done. The CocoaPods sunset (PR from `chore/swift-package-manager`:
  both platforms on Swift Package Manager, no Podfile left); the failing `flutter build macos --release`, the legacy
  signing config and the dead scaffold assets (PR from `chore/apple-build-config`, stacked on #87). The Flutter
  version state is D9; 3.47 is D11.
- **Track C, reliability and tooling, off `master`:** a refused write queued by an earlier launch was dropped silently
  (PR #88 from `fix/rejected-write-earlier-launch`, reviewed: a journal on the device, checked on the next launch);
  the minimatch override broke firebase-tools glob paths, and nothing checked the index file against the queries
  (both in PR #90 from `chore/minimatch-and-index-check`, stacked on #88: a range-keyed override, and
  `test/firestore_indexes_test.dart`; no app change, so no e2e).
- **Docs:** land `design/day-dial-system` (the published design system's sources) on `master`.

**UNDECIDED:** none then: round 9 was picked on 2026-11-07, every earlier call on 2026-11-06; `r7-ci` and round 5 are
moot. Other languages, then unasked, were decided in round 10 (U4).

**Blocked on Jack:** the paid Apple team and the release (B2, B3).

Housekeeping rides along with whatever PR touches it: deleting fixed tech-debt files and shipped idea files with their
README lines, and the recount (`tech-debt/README.md`).

## Jack's calls, round 1 (2026-11-03)

Picked on the pitch page; the page keeps the options and costs each was chosen from.

- **C1. Rules deployment** (`rules-deploy`): **CI deploys rules and indexes on merge to `master`.** On since
  2026-11-04; the rule is in `CLAUDE.md`.
- **C2. Today with 1 or 2 vices** (`today-few-vices`): **bars below 3 vices, the radar from 3 up.** Superseded by
  `r6-ui-direction` (round 6).
- **C3. Save timeout** (`record-timeout`): **close the dialog and say the entry will sync.**
- **C4. Undo duration** (`undo-duration`): **8 seconds.**
- **C5. Clean day** (`clean-day`): **quietly positive**: a green tint and short encouraging copy, no streak pressure.
- **C6. Platforms** (`platforms`): **iOS first, through TestFlight.** "Delete the rest. Add a MacOS target too,
  fully-supported." Android and web go.
- **C7. `functions/`** (`functions`): **delete it** and close its Dependabot PRs. `functions/` came back for
  `r8-bead-size` (2026-11-06, below).
- **C8. Licence** (`licence`): **proprietary, all rights reserved.**
- **C9. Stale git state** (`git-cleanup`): **archive the stashes, then clean**; keep `copilot/fix-9`.
- **C10. E2E in CI** (`e2e-ci`): **in CI on `master` after merge, debounced** (Jack, 2026-11-06, superseding "local
  only"; `e2e.yml`, #96). The rule is in `CLAUDE.md`.
- **C11. PR previews** (`pr-previews`): **drop them.** Moot once web goes (C6).
- **C12. Quantity** (`quantity`): **greater than 0** on a new activity, so a free day is not logged as a zero entry.
- **C13. Vice name length** (`name-length`): **60 characters at most.**
- **C14. Vice ownership** (`vice-owner`): **check it**: an activity's vice must belong to the person logging it.
- **C15. Positioning** (`positioning`): **a neutral journal, for seeing trends and learning about yourself.** Jack's
  note, condensed: shore up the journal and trend side significantly; cutting down may coexist, but the journal is
  the point. He wants intelligent insights: what causes use (calendar integration for meetings; triggers picked from
  options that get more specific as you click through, remembering your most common ones, or free text); what follows
  from using one vice against another (Apple Health: sleep, HRV, heart rate and the like, including historical data,
  disambiguating which vice a health effect correlates with over time). Maximum granularity. Privacy is not a concern
  as long as sensitive processing and storage stay on the device; it can all be regenerated from the raw data.
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer. Now 18+ (`r2-age`, below).
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes**, optional or, with a first-launch migrator, mandatory; the
  rule is in `CLAUDE.md`.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** The brand is Penchant (`r2-brand`,
  round 2).

## Jack's calls, round 2

- **`r2-web-site`** (2026-11-03, in chat): **take the live web site down now.** It is Firebase Hosting on the
  production project, out of Claude's reach under the hard rules, so Jack did it; the site returns 404 (checked
  2026-11-04). Done.
- **`r2-icon`** (2026-11-05, in chat): **candidate 38**, the Today radar's coloured segments with spokes running past
  them, centred, on a light background, picked from 38 candidates on the icon sheet
  (https://claude.ai/artifact/JGnHCcPxaTLHKiyZeFgNmK, sources on the tag `archive/mockup/icon-sheet`). Shipped as the
  iOS and macOS icon in the PR that records this; the sources are `assets/icon.svg` and `assets/icon-macos.svg`.
  Independent of the brand. Done.
- **`r2-brand`** (2026-11-05, on the pitch page https://claude.ai/artifact/NBsbWYMVPh2phzS3wKDRCH, no note):
  **Penchant**, with the recommended App Store subtitle **"Habit journal & sleep insights"**. Applied to every identity
  string in #81, the bundle IDs in #84. Backups if the name proves unusable: Kenning, then Sounding. It settles C19.
  **`r2-brand-icon`** (2026-11-06): "We already have a brand I like": the icon stays `r2-icon`'s candidate 38. Habit
  names in mock-ups are made up, and the mock-up's "Tracker" is a placeholder.
- **`r2-presets`** (2026-11-06): **A, the plain names** (Alcohol, Coffee, Cigarettes, Vape, Cannabis, Energy drinks,
  Sweets, Gambling) in a first-run flow for an account with no habits: intro, presets plus "Something else", the
  disclaimer, an optional first log. Built in the PR from `feat/onboarding-presets` (`lib/onboarding/`).
- **`r2-mac-config`** (2026-11-05): the Mac shares the iOS app's Firebase registration and config file (the
  recommended side; details in `CLAUDE.md`).
- **No trademark search** (2026-11-05, Jack): none will be done, professional or otherwise. Don't raise it again.
- **Wording** (2026-11-05, Jack, #81): the UI says **"habits"**, not "vices"; code and data keep `vice` (`CLAUDE.md`).

## Jack's calls, round 6

- **`r6-ui-direction`** (2026-11-05, on the UI overhaul pitch page https://claude.ai/artifact/23uvjtPyS7TqPvXaEBw9Px;
  read from its `picks` collection): **Day Dial**, the day as a 24-hour dial with each entry a coloured bead at its
  time. It settles **`r2-today`** (A, the journal layout, superseded) and supersedes C2 (`today-few-vices`): the radar
  and its bars left Today in #83, and round 5 (`r5-radar-inset`, `r5-key-height`, `r5-key-always`) is moot. It allows
  the one-tap **"log one"** (`CLAUDE.md`). Chrome is ink on paper and the five icon colours mean habits only; a habit's
  colour follows its creation order, computed on the device with no stored field (the scheme is in `CLAUDE.md`). Units
  stay the existing enum; new units are `r2-data-model`. Built as the queue's item 1.
- **Contrast** (2026-11-05, in chat): **every colour pair meets WCAG 2.2 AA in both themes**: 4.5:1 for text, 3:1 for
  icons, meaningful graphics, control edges and focus. Fix, never flag; the habit colours keep the icon's five hues
  (lightness, rims and inks may change). The pairs are `docs/design-system/day-dial/project/contrast-pairs.json`,
  checked by `tools/contrast-check.py` and `test/contrast_test.dart`; a new use of a colour adds its pair there. One
  exception: `r8-clear-spokes` (2026-11-06, below).

## Jack's calls, rounds 2 to 4 and 8 (2026-11-06)

Picked on the pitch page (https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs); the page keeps the options and costs.
Notes are Jack's, condensed. `r2-presets`, `r2-brand` and `r2-brand-icon` are under round 2; `r2-today` under round 6.

- **`r2-privacy`**: **no privacy policy for now.** Penchant is for Jack's own use ("I'm not actually going to put it
  on the App Store; it's just for me"): build it with production polish, but the store, legal and payment work
  (privacy-policy details, App Store listing, Pro and billing, TestFlight) stays undone until and unless he decides to
  sell.
- **No paid Apple Developer account for now** (Jack, 2026-11-06). What waits on it is under For Jack to do.
- **`r2-testflight`**: **Production** (no separate beta project). "Just Do It Right." Moot until there is a paid team.
- **`r2-signin`**: **guest start, link an account later, plus Sign in with Apple.** Jack's production data sits under
  an email-and-password account and has to end up on his Apple ID (Sign in with Apple). Linking the Apple credential
  to the signed-in email user keeps the uid, so the data needs no copy. Sign in with Apple needs the paid team; guest
  start and linking an email do not.
- **`r2-e2ee`**: **yes, before 1.0**: names, units, amounts and later notes sealed on the device (AES-256-GCM); dates,
  IDs and the owner stay plaintext. Key in iCloud Keychain plus a printable recovery key. Amounts stay plaintext after
  all (Jack, 2026-11-06, for `r8-bead-size`); `CLAUDE.md` lists the sealed fields.
- **`r2-e2ee-key`**: **a Today card after a week, and Settings any time.**
- **`r2-data-model`**: **optional fields, plus a first-launch migrator (for a vice category) and a decimal amount**
  next to the whole-number quantity.
- **`r2-days`**: no option picked; the call: **if nothing is logged, treat the day as clean.** No check-in and no
  days collection.
- **`r2-triggers`**: **Areas of life** (Social, Feeling, Work, Body, Routine, Place, Craving), against the
  recommended B.
- **`r2-age`**: **18+** (Apple retired 17+ in July 2025, superseding C16's "17+"); neutral framing with a disclaimer
  (C16). **`r2-mac`**: **the Mac ships with iOS 1.0 if its e2e is green.** Both moot until a release.
- **`r2-pro`**: **the analysis layer, $24.99**. **`r2-billing`**: **StoreKit 2 directly.** **`r2-applock`**: **app
  lock and discreet mode both free.** Parked with the store work; nothing to build now.
- **`r2-crash`**: **Crashlytics only.**
- **`r2-cli`**: **upgrade the global Firebase CLI** (`npm install -g firebase-tools@latest`).
- **`r3-delete-copy`**: **ship the deletion wording as written.** **`r3-verify`**: **nothing requires a verified
  email.** **`r3-cache`**: **keep the on-device cache.** **`r3-attest`**: **App Attest with DeviceCheck fallback, as
  built.** All as built; no work.
- **`r4-server-time`**: **the phone's clock, as built.** **`r4-vice-cap`**: **no cap for 1.0.** No work.
- **`r4-weekly`**: **round the range down to whole weeks** (30 days shows 28), against the recommended A. Built (queue
  item 4).
- **`r8-clear-spokes`**: **25%, as the mock-up**, against the recommended A: on a clear day the major spokes are
  decoration (the 00/06/12/18 labels give the time), classed so in `contrast-pairs.json`, an exception to the contrast
  rule for that state only. Built (queue item 4).
- **`r8-coach`**: **don't build the "Tap Log" pill.**
- **`r8-bead-size`**: C, **a typical amount stored per habit**, on Jack's terms: not editable, computed by a scheduled
  job each month over the last 3 months only. More generally, precompute per-user reads wherever possible into a
  single document per user, to cut reads and load times, especially for the graph and calendar. How it runs: **a
  Cloud Function** (Jack, 2026-11-06, over the app refreshing the document itself). Built as `monthlySummaries`, in
  the PR from `feat/bead-summary-function`.
- **`r8-tally-target`**: **44 x 38, as built.** No work.
- **`r8-mac-window`**: **about 1200 x 780, the split view by default.** Built with 1g in #145 (D7).
- **`r8-mac-keys`**: **Cmd-1 to Cmd-9 log one of the Nth habit now**, listed in the menu bar. Built (queue item 4).

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
  height. Jack picked B as presented, with the pitch's two conditions (Claude's, in its recommendation): cap the dial
  near 480 pt, and keep Today's column at 504 pt at 1200 x 780. Built from `design/mac-fullscreen-b` (the tag
  `archive/design/mac-fullscreen-b` once archived; U1).
- **`r10-widget-top`**: D, **the top habits are the most logged in the last 30 days, overridable by hand in the
  widget's settings.**
- **`r10-widget-undo`**: B, **a 5-second Undo where you tapped**, on each surface (widget, control, menu bar row). If
  WidgetKit cannot hold and revert that state, Claude's fallback is C (the app's Undo on the Mac menu bar only), said
  so.
- **`r10-intents`**: A, **Siri, Shortcuts and the Action button through the same log intent**, built with the widgets.
- **`r10-mac-widgets`**: A, **macOS widgets from the same code**: the same WidgetKit code as a Mac extension, built
  with the iPhone widgets, for the desktop and Notification Centre. It depends on the journal key reaching the Mac
  (P2). Jack: "Widgets for the Notification Centre are useful to me."
- **Mac menu bar after quit** (2026-11-08): Jack: "the menu bar app should still be present even when the app is
  cmd+q'd too." Built as a login-item helper app (queue item 6); a log made with the app closed is written within
  seconds by a hidden flush-mode launch (PR #167).
- **`r10-reduce-motion`**: B, **a Follow system / Reduce / Full row in Settings, saved per device** in
  shared_preferences like Appearance. PR #153 (`feat/reduce-motion-setting`): Full covers only the app's own
  controllers and pushed pages, since iOS Reduce Motion scales default controllers to 5% and no release-mode API turns
  that off (D16).
- **`r10-languages`**: A, **English only** (register: `no-localizations-delegates-or-supported-locales`).
- **`r10-analytics`**: A, **none** beyond Crashlytics.
- **`r10-reminders`**: B, **one optional daily nudge**, off by default. Jack: long-pressing the notification should
  offer something like "Nothing further" or "Clean day"; it needn't do anything, but should feel good to press.
- **`r10-pitch-branches`**: C, **land the Day Dial mock-up files, tag the rest as `archive/*`, then delete those
  branches.** The files are in `docs/pitch/mockups/ui-overhaul/day-dial/`; each other pushed pitch-source branch with
  no PR (`mockup/*`, `design/ui-overhaul-*`, `design/mac-fullscreen-*`, `spike/*`) is tagged `archive/<branch>`. The
  tag and delete commands are in the PR from `docs/round-10-picks`, for the main session to run after it merges.
- **`r10-release`**: B, **wait**: cut 0.2.0 once the picked Mac fullscreen layout and PR #133 (AutoFill) land, then
  install it on Jack's iPhone and Mac. Its first launch runs the sealing migrator over his real journal.

Later the same day, in chat, on the widgets (#158) and the nudge (#156):

- **Background refresh, battery-light.** Jack: "Background refresh now. Don't use up all of my phone's battery with
  it." A log from a widget, control or Siri reaches Firestore without opening the app. No polling, no silent push.
  Built in #158: on iOS a `BGAppRefreshTask` asked for only while logs are queued, timed by the system; on the Mac,
  while the app runs, a retry every 15 minutes or more at utility priority, only while logs are queued. Since
  reworked (PR #166, PR #167, `r11-ios-widget-sync` B); the current mechanism is in queue item 6.
- **Habit names and counts in the App Group, plaintext on the device, are acceptable.** The widgets' snapshot and
  queue stay as built in #158 (they clear on sign-out).
- **The Lock Screen shows the top 3.** As built in #158.
- **The daily nudge fires every day regardless**, even on a day already logged. Jack: "in case something was
  missed". **"Clean day" just dismisses** (option c). Both as built in #156; no change.
- **Log widget = Hero with Glow** (Jack 2026-11-08: "B, with C's glow"). The first habit is a dial with a +
  badge, the rest are pills with their count and a + button, each on a soft glow of its colour. Renders in
  `docs/pitch/round-11/log-widgets/final/`.

## Calls waiting on Jack (UNDECIDED)

None on the pitch page. Every call is picked: rounds 1 to 4, 6 and 8 on 2026-11-03/05/06, round 9 on 2026-11-07, and
round 10, which decided U1 to U8 in the overnight list (Jack's calls, round 10, above), on 2026-11-08. Round 5 and
`r7-ci` are moot.

- **The client API key's restrictions** (UNDECIDED; not yet set): they live in the production project's Google Cloud
  console, which Claude does not touch. Recommended, not decided: an iOS application restriction to
  `com.screendead.penchant` and an API restriction to the Firebase APIs the app calls. Reasoning in `CLAUDE.md`
  "Client API key".

## For Jack to do (not decisions)

- **Orphaned guest data cleanup runs as a dry run** (`dailyOrphanCleanup` in `functions/index.js`, 04:30 UTC;
  deployed 2026-11-07, first run 2026-11-08; overnight list B1). It logs "Orphan cleanup would delete" with each uid
  and its document counts once two runs a day apart find the account gone. Jack reads those logs for a few days
  (Claude can't read production logs); then Claude pitches the one-line flip `DELETE_ORPHANED_DATA = true` in its
  own PR.
- **`monthlySummaries`'s runtime account** (the default compute service account) needs Firestore read and write
  (`roles/datastore.user`), which it holds unless it was trimmed.
- **Done, 2026-11-06:** Jack reported the checklist done. Checked from here: Dependabot PRs #22 and #42 are closed,
  and the CLI's configstore no longer maps the main checkout to production (`firebase use --clear`, checked again
  2026-11-08). The console steps (Email Enumeration Protection, the email templates, a budget alert) can't be seen
  from here; taken as done on his word.
- **Still open:** the main checkout still shows `macos/Runner.xcodeproj/project.pbxproj` modified (the 2026-11-04
  signing attempt; #47 carries the team). `git checkout -- macos/Runner.xcodeproj/project.pbxproj` in
  `~/development/tracker` discards it; Claude leaves it, as it is Jack's working tree.
- **Waits on a paid Apple Developer Program team, which Jack is not getting for now** (Jack, 2026-11-06): the App
  Attest entitlement (a personal team can't sign it; once there is a team Claude adds
  `com.apple.developer.devicecheck.appattest-environment` = `production` and proves the release build signs),
  registering the app with App Check (Team ID, a DeviceCheck key) and then enforcing it on Firestore, TestFlight,
  Sign in with Apple, and the App Store.
- **Waits on a release:** the domain variant (`penchant.com` is held, `penchant.app` parked) and the support and
  legal pages it addresses, an App Store search for Penchant, and the privacy-policy and support details
  (`r2-privacy`).
- **The old app install:** the build under `com.screendead.tracker.tracker` stays on the phone beside Penchant until
  Jack deletes it; its two iOS registrations in the console can go once it is, and that registration's API key stays
  valid until revoked there.

## How to test here

The rules (never against production; emulators under `demo-tracker`; Firebase docs first; e2e in CI after merge) are
in `CLAUDE.md` "Hard rules", and the commands, ports and CI triggers in its "Commands".
`GeneratedPluginRegistrant` is gitignored on both platforms; `flutter pub get` and every flutter build regenerate it.

## Where the backlogs are

- `tech-debt/README.md`: what is wrong, by class and severity.
- `ideas/README.md`: what to build next, as pitches, ordered as a roadmap to a paid release.

Each README states its own conventions.

## Thoughts

- The app is a small Flutter + Firestore codebase (about 3,000 lines in `lib/`). Tests now exist at three levels
  (rules tests, unit and widget tests, 31 e2e tests), but most of the app is still untested. Most of the work before
  release is making it trustworthy, not adding screens.

## Set aside, with reasons

- **Rebasing or force-pushing the recovered feature branch** to tidy its history: it was already pushed, and
  force-pushing needs Jack. It merges `master` in instead.
- **Android release, the web app, PR previews** (C6, C11): removed 2026-11-03; re-add only on a new call. Cloud
  Functions, removed with them (C7), came back with `r8-bead-size` (Jack, 2026-11-06).
- **Harm-reduction framing, and the moderation, alcohol-only and quit-counter positionings** (C15, C16): the app is a
  neutral journal. Goals and limits survive as an optional, later feature.
