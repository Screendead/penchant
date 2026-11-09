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

Each goal is clear or follows from Jack's calls below. Subagents write PR bodies to uniquely named scratchpad
files: the scratchpad is shared, and a generic `pr-body.md` once put one PR's description on another.

1. **The Day Dial UI overhaul** (`r6-ui-direction`, below), from the mock-up and its Flutter notes (`CLAUDE.md`,
   design). One PR per step, in order; every screen works between steps, and each PR keeps `tools/e2e.sh` green by
   fixing the tests its screens break. Status 2026-11-08: 1a to 1e merged, 1f and 1g partly; left is D1 to D5 in the
   overnight list. The step notes below are history.
   - **a. Theme foundation** (#79): tokens, light and dark `ThemeData` (the mode is now `r9-appearance`'s choice),
     bundled fonts, the habit colour function, hard-coded colours replaced.
   - **b. Today** (#83): the dial (`CustomPainter`, beads at their times, now-hand, clear-day ring), tally rows with a
     `+` each, the one-tap "log one" action (the layout-neutral half of one-tap logging), the Log button and its fan,
     the amount sheet replacing the record dialog for new entries, and the calendar sheet. #83 shipped all but the
     amount sheet: until D1 (#148) a held wedge (or More, past eight habits) opened the record dialog with the habit
     chosen. Left then: the amount sheet (D1, with 1d's editor, which reuses it), the SyncBadge pill (#94), merging a
     dense hour's beads into one arc above about 48 entries (D3), docking the Log button on the Trends sheet (1c). The
     offline banner and the day's pending note stay. Bead size was against the habit's median entry on the shown day
     (no extra read); "your usual" ghost beads and a cross-day typical would cost a 7-day query; `r8-bead-size`
     replaced both (item 4).
     Fidelity pass (#94, `feat/today-fidelity`), after Jack found Today unlike the mock-up: the Penchant wordmark menu
     (Habits, Settings, sync footer) replaces the drawer, the Synced pill uses `waitForPendingWrites`
     (`syncStatusProvider`), the mock-up's spacing fits five tallies above the Log button on a 390 x 844 phone, light
     shadows, stroke icons, dimmed zero pips. Side by side in `docs/pitch/mockups/ui-overhaul/day-dial/fidelity/`;
     re-render with `tools/fidelity/`. Still different, by the 3:1 floor: the clear day's major spokes, pip and wedge
     rims, the sparkline's daily line. Jack's round 8: no coach pill, clear-day majors at 25%, bead size against a
     stored typical (`r8-bead-size`).
   - **c. Trends sheet** (#89, `feat/trends-sheet`, stacked on #83): replaces the Graph tab, over Today, with habit
     chips, range and Day/Week segments, the average stepper, stats, "when it happens", a day point opening its dial,
     and the Log button docked on its edge; weeks per `r4-weekly` B (item 4). Left for 1f (D2): the chart's morph
     between ranges (fl_chart tweens only equal-length series, so a range change snaps) and the day's container
     transform with the `animations` package (it fades in place).
   - **d. Habits, history and the entry editor** (#100, `feat/overhaul-1d-habits`): Manage Data becomes Habits; Habits
     and history in the card style; swipe-to-delete with Undo on history rows and Undo on the editor's delete (the
     register's inconsistent-delete item is gone); Archive and Edit habit moved to the history page; editing reuses
     the amount sheet. Left: the amount sheet (D1; the editor kept its form), the history page's "Last 30 days"
     summary card (D4), page transitions (1f, D2).
   - **e. Auth and settings screens** (#99, `feat/overhaul-1e-account`): one sign-in screen with a segmented control and
     the password checklist; Settings and Account Settings in the card style; copy as written (`r3-delete-copy`); a
     3:1 keyboard focus ring (a 2 pt accent ring in place of Material's 12% overlay) on card rows, the sign-in segments
     and the slider; the unused navigation-bar themes gone with the sign-in BottomNavigationBar. Left: the Habits and
     history `ListTile`s (1d's files) show only Material's overlay. Side by side in `fidelity/signin-*`, `signup-*`,
     `settings-*` (`test/fidelity_account_render_test.dart`).
   - **f. Motion polish:** bead travel, day sweep, springs, page transitions (the mock-up's notes add the `animations`
     package), the reduce-motion fades.
   - **g. e2e rewrite:** rebuild `integration_test/` around the new flows (fan gestures, dial semantics, the sheets), on
     iOS and `E2E_DEVICE=macos`.
2. **The macOS split view: done** (#92, merged 2026-11-06, `feat/macos-split-view`; from `notes.md`, "macOS"; how it
   works: `CLAUDE.md`). The Mac runs the e2e suite on the split view, iOS on the sheet.
3. **Bundle IDs to `com.screendead.penchant`: done** (#84, merged 2026-11-06): Runner and RunnerTests on both platforms,
   the Penchant `GoogleService-Info.plist` on both, `firebase_options.dart`, the macOS keychain group. The idea file is
   deleted; its leftovers (the domain variant, an App Store search on a device) went to the support-pages and
   TestFlight ideas and For Jack to do. iOS e2e 31/31 and a signed release build pass; the review's full
   `E2E_DEVICE=macos tools/e2e.sh` (2026-11-06, load about 7) passed 31/31 with 34 registrations. Under load 40 and up,
   3 of 70 registrations timed out at 30 s (Homepage never appeared), beside 30 s timeouts in no Auth code (a server
   count, a dialog close), so load is the likelier cause than the keychain. If the hang returns on a quiet machine, the
   macOS keychain access group (`macos/Runner/*.entitlements`) is the one ID-specific piece on Auth's persistence path.
4. **The work from the 2026-11-06 picks** (rounds 2 to 4 and 8, below): `r8-clear-spokes` B, `r4-weekly` B (deletes
   the register's oldest-weekly-bucket item), `r8-mac-keys` B, `r8-mac-window` B, Crashlytics (`r2-crash` A), guest
   start with linking an email later (`r2-signin`, the part that needs no paid Apple team), onboarding (`r2-presets`
   A), the data model (`r2-data-model` B), trigger tagging (`r2-triggers` A), and end-to-end encryption (`r2-e2ee` A,
   `r2-e2ee-key` A). Status 2026-11-08: all merged (#103 to #107, #109 to #118, #124, #130; `r8-mac-window` in #145,
   D7). `r8-bead-size`'s monthly summary is built (PR from `feat/bead-summary-function`); the dial sizes beads against
   its typicals. Sign in with Apple waits on the paid team (For Jack to do).
5. **The rest of the register**, medium then low, one class per PR.
6. **Soon: iPhone widgets, Control Centre controls and a Mac menu bar app** (Jack, 2026-11-07). Build all:
   - **Home and Lock Screen widgets** in every WidgetKit size (small, medium, large, extra large on iPad, and the Lock
     Screen's circular, rectangular and inline). One kind shows **last week's usage of every habit**; the other
     **records one usage of one of the top 1, 3 or 8 habits** (the size picks how many).
   - **Control Centre controls** (iOS 18 `ControlWidget`), one button that logs one usage of a chosen habit.
   - **A macOS menu bar app**: the dial on top, the habits below. Clicking a habit logs one usage at the current date
     and time.

   Constraints: native Swift targets (WidgetKit, App Intents), because Flutter does not run in an extension. Writing
   an activity needs no key (its fields are plaintext under `r2-e2ee`), but habit names are sealed, so showing them
   needs the app's Firebase Auth session and the E2EE key through a shared Keychain access group and an App Group. The
   free signing team can sign App Groups and app extensions on iOS (proven 2026-11-08 on `spike/widget-app-group`,
   commit becdcaf: extension `com.screendead.penchant.widgets` read what the app wrote to App Group
   `group.com.screendead.penchant` on Jack's iPhone; `tools/add-widget-target.rb` there generates the target); Apple's
   docs give free teams macOS App Groups, but whether sandboxed macOS needs a TEAMID-prefixed group name is unchecked.
   Read Apple's current WidgetKit, App Intents and ControlWidget docs first. Jack's round 10 picks settle the open
   questions (`r10-widget-top` D, `r10-widget-undo` B, `r10-intents` A, `r10-mac-widgets` A; round 10, below); whether
   WidgetKit can hold and revert the Undo state is unchecked. The idea file is
   [widgets-and-shortcuts](ideas/growth-later/widgets-and-shortcuts.md). Status 2026-11-08: per Jack (2026-11-08: "the
   menu bar app should still be present even when the app is cmd+q'd too"), the Mac menu bar is a native login-item
   helper (`macos/PenchantMenuBar`, a SwiftUI `MenuBarExtra` embedded at `Contents/Library/LoginItems`, registered
   with `SMAppService.loginItem` at each app launch). It reads the widgets' App Group snapshot and queues logs in
   their `LogQueue`, which the app writes, sealed, on its next flush. With the app closed, the helper launches it
   hidden (no window or Dock icon) to flush and quit (`FlushMode`, PR #167; Jack 2026-11-08: "do it properly"), and
   the run leaves its outcome in the App Group: the helper retries a `retry` when the network returns, on wake and on
   a backoff of about an hour, and says "open Penchant to sync" for a `blocked` one. The in-process popover (#157,
   #163) is gone, and with it the private `enableMultiView` call, which also sent VoiceOver to the wrong view
   (`FlutterEngine.mm`, `update_semantics_callback2`). On iOS the log intents are `LiveActivityIntent`s (PR #166), so
   a widget, control, Siri or Shortcuts log runs in Penchant's process, launched in the background if need be; it
   flushes once the Undo hold passes, under a background task, with `BGAppRefreshTask` as the fallback. Jack's "do it
   properly" (2026-11-08) settled `r11-ios-widget-sync` as B. Both platforms installed as build 964; neither path
   proven on a device yet.

7. **Insights, built free** (Jack, 2026-11-08: "build it free for me, we can paywall later"). The Pro features ship
   unlocked; the paywall and StoreKit wait until he decides to sell. Apple Health works on the free team: a signed probe
   build on 2026-11-08 got a profile granting `com.apple.developer.healthkit` and background delivery. One small,
   resumable PR per step, merged on green and ticked here. Health and every source below stay on the device:
   nothing they read goes to Firestore, analytics or crash reports.
   - **a. Engine core** (merged, #170; pure Dart, `lib/insights/`): per-day series from the decrypted journal, a "what
     follows" comparison of an outcome on days after each habit against days without, attributed per habit, and a
     refusal to report below a minimum sample or inside the noise (`ideas/insights/insights-engine.md`).
   - **b. Health reading** (merged, #171; iOS Swift channel): the entitlement, usage string, permission asked from the
     Insights screen only, daily and nightly aggregates (`HKStatisticsCollectionQuery`) for sleep stages, HRV, resting
     heart rate, respiratory rate, oxygen, wrist temperature, steps and energy, kept in an on-device store
     (`ideas/insights/apple-health-correlation.md`, recommendation B with C's aggregates).
   - **c. Insights screen** (merged, #173): connect Health, then show the engine's findings; empty Health reads as
     "no data yet". Stills in `docs/pitch/round-11/insights/`. Not run on a device: the real
     HealthKit sheet and read, and the engine in another isolate, are proven only by widget tests with fakes.
     Findings are now corrected for many tests at once (#175, merged): Benjamini-Hochberg at q = 0.1 across every
     habit x outcome on the page; on pure noise (5 habits x 9 outcomes, 400 seeds) false findings fell from 5.0% of
     checks (91% of reports showing one) to 0.23% (8%). The autocorrelation-corrected sample size and the
     block-bootstrap interval of gates 2 and 4 are still not built; the practical-size floor is (below).
     Spans with faded logging (#181, open): a trend and a second-half level in the model, and a refusal ("Used far
     more at some times than others") for a habit used over 3x as often in one half (p < 0.01); noise rate unchanged
     (0.24%, 8%). Review fix: the 3x check also runs on days gone without (patchy early logging of a daily habit),
     and the test allows for runs of use; even-use false refusals stay under 1% (`tools/insights-calibration/`).
   - **Whole history and Copy as text** (Jack, 2026-11-09: "i've got more than a year's worth of data"; #179, open,
     `feat/insights-whole-history`): the journal query runs from 2000 (the date picker's floor) to today, keyed on
     the day; Health is read from September 2014 (HealthKit's launch) in calendar-year calls, 13 today; the page says
     "From <first entry> to today" (the earliest entry of a habit the page shows), and "Copy as text" puts the
     findings and refusals on the clipboard on a tap. The journal is read once per open with `get()`, not listened
     to, and the Health loop stops when the page is left. Not run on a device: the 13 HealthKit calls' time on a
     phone with years of data, and the one-time read's cost over a multi-year journal (every document once per
     open), are unmeasured.
   - **Ask again for new Health types** (`fix/health-reask`, #184, open): Health connected before #178 was never asked for heart rate; the card now offers "Allow new Health data" when HealthKit's `getRequestStatusForAuthorization` says `.shouldRequest` (a stored read-types version decides when it can't tell), and names where to manage access. Not run on a device.
   - **Archived habits hidden** (Jack, 2026-11-09: "Archived habits shouldn't show any cards"; `fix/insights-hide-archived`, #189, open): no card, no refusal row, out of the Benjamini-Hochberg family; their uses stay as covariates.
   - **Fewer, larger cards** (Jack, 2026-11-09, on his real data: about 27 cards, many near-duplicates too small to
     matter; #192, open, `feat/insights-floor-and-cards`). After Benjamini-Hochberg and every existing refusal, untouched: a
     finding under its outcome's floor (`metricFloors`, `lib/insights/insights_report.dart`) is refused as "Too small
     to matter: under 10 min a night of core sleep", ranked first among a habit's refusals. An amount or a time is
     judged at effect / step x the interquartile range of the habit's day totals or last-use minutes over the days
     used; a use or hours-after effect as is. Floors, **Claude's defaults pending Jack's review**: sleep (asleep, in
     bed, awake, core, deep, REM) 10 min; HRV 3 ms; resting and sleeping heart rate 1 bpm; hours-after heart rate
     2 bpm; breathing 0.3 a minute; blood oxygen 1 point; wrist temperature 0.1 °C; steps 1,000; active energy 50
     kcal. Then one card per habit and family (sleep; heart: HRV, resting, sleeping and hours-after heart rate;
     breathing with blood oxygen; temperature; activity), led by its largest finding by effect / floor, with range
     and days for the headline alone and the rest as short lines ("More per extra drink: REM sleep 4 min less",
     "Later last use: time asleep 11 min less per hour"). Cards sort by headline effect / floor; six show, the rest
     behind "Show N more". Open questions: a habit logged at one amount on most days (but 7 or more days off it)
     has an interquartile range of 0, so every amount finding of it is refused as too small; the calibration rates
     above were measured before the floor and are not rerun (the floor can only lower them).
   - **d. Health history backfill and incremental sync** (anchored queries, then background delivery).
   - **e. Calendar** (`ideas/insights/calendar-integration.md`). **f. Weekly review**, then **g. trend overlays**.
   - **Checkpoint 2026-11-09 (resume here).** Merged and on both devices (build 985): a #170, b #171, c #173, the
     many-comparisons correction #175 (Benjamini-Hochberg, q = 0.1). Open or in flight, in merge order:
     1. **#178** `feat/health-samples`: timestamped samples, paged; nightly sleeping heart rate. Review, merge, install.
     2. **#179** `feat/insights-whole-history`: whole journal history, Health in yearly calls, Copy as text.
     3. **`fix/insights-span-guard`** (check whether its PR exists): a time-trend term and a "used far more at
        some times than others" refusal, so a habit whose logging fades is not credited with a step change in an
        outcome; and a too-few-days refusal that says which side is short.
     4. **Sleep double count, after #178:** `HealthDays.sleepRows` unions every source's asleep periods, so another
        app's single asleep span over a night covers the Watch's awake periods (synthetic: Watch core 23:00-03:00,
        awake 03:00-04:00, core 04:00-07:00 gives asleep 420; add another source's asleep 23:00-07:00 and it gives
        480 with awake 60). **`fix/health-sleep-source`, PR #182:** each sleep (not night) keeps one source's asleep,
        stages and awake: the first source, in one order over the whole read (stages, a Watch, most staged, most
        asleep, bundle id), whose span takes in 3/4 of the sleep's asleep time from every source, else the one with
        the most asleep; in bed from that source or else the one with the most; the sleep is keyed by its chosen
        source's end; sleeping heart rate uses the same choice. Review, merge, install.
        Then **#186** `fix/health-sleep-sessions`: Watch-less sleeps before a Watch main sleep drop; Jack picked B (2026-11-09): drop app-only sleeps before the Watch's main sleep; later ones stay.
     5. **i. Dose and timing: done when this PR merges** (#185, `feat/insights-dose-timing`). Then **j**
        (#187, `feat/insights-hours-after`, below). Jack, 2026-11-09: a habit
        used every day must still yield insights: amount per day, time of first and last use, the hours around each
        use (j), co-occurrence with other habits (l), and the before and after of a streak's start (m).
     6. **#192** `feat/insights-floor-and-cards`: the effect-size floor and one card per habit and family (Fewer,
        larger cards, above). Review, merge, install; Jack to review the floors.
     7. **Next for item 7: build 1A + 2C on top of the trim (#192)**: the round-12 decision (Direction, below). Not
        started.
     8. **Then: floors from the literature** (Jack, 2026-11-09: each floor is the smallest change shown to have
        *some measurable effect*, as a number or a % of the person's usual, so a card can also say what that size
        is likely to do). Replace #192's reasoned floors with sourced ones per metric, citing each. Where a source
        reports a share of baseline, use the person's own usual. Check each floor against the person's
        night-to-night noise so a floor never sits inside it. Add one line per card on what an effect of that size
        has been shown to do, with the source. The research comes first, as an agent pass with citations; then a
        small engine and copy PR. Not started.
   - **Finer than days** (Jack, 2026-11-09: days with and without a habit are "not granular enough"; check whether
     health signals *precede* use, and what happens in the minutes and hours after a use). Engine steps, one PR each,
     after the many-comparisons correction and the whole-history range:
     - **i. Dose and timing: this PR** (#185, `feat/insights-dose-timing`). Two more comparisons per habit and outcome, in
       the same report and the same Benjamini-Hochberg family, both among days with the habit so a daily habit gets
       a slope: the day's amount (`doseFollows`, per unit, or per a 1-2-5 step when the totals spread over more than
       3 units or under half of one, never a fraction of a unit when every total is whole), and the clock time of the
       day's last use (`lastUseFollows`, per hour later; the day's amount is a covariate). Both key a use before
       05:00 (`lateUseCutoffHour`) to the evening before, for the amount as for the time; the used/not-used
       comparison still keys on the calendar day. Same trend and month terms and other habits' indicators. Refused
       as steady when the amount has under 7 days off its commonest value or a spread under 10% of its mean, or the
       time has an sd under 30 min or under 7 days an hour from its median; a time that moves with the amount
       (uses spaced through an evening from a set start) is refused as "later on days with more" rather than
       blamed on another habit; an entangled refusal names the habit whose removal frees the column. An amount or
       time finding that one day decides is refused as within the noise: when the most influential day (by DFBETA)
       moves the effect by over one standard error, the fit without it must still exclude zero. The page keeps one
       reason per habit: a habit with any finding is not listed; otherwise entangled, chance, uneven, noise,
       steady or follows-the-amount, too few days, and on a tie the used/not-used comparison's.
       Measured (`tools/insights-calibration/dose_timing_test.dart`, sd-1 noise, 120 days): one check alone finds
       5.1% (dose) and 5.1% (time) on noise; dose 0.2 sd per unit found 70% (60 days: 41%), time 0.1 sd per hour
       93%; amount rising with the months while the outcome steps 1 sd a month: 5.6% (chance only). One extreme day
       (a 12 among 1 to 4, or a lone 06:00 use, with a 3 sd night after it): 7.5% each, from 39% and 50% before the
       one-day check. Whole page on noise (Coffee, Tea every other day, Water daily; 9 outcomes; 28,809 checks over
       400 seeds): 5.3% raw, 0.17% of checks and 9.8% of reports after BH. Not covered: a change in amount and
       outcome inside one month (step at day 50: 19% false findings; step m). The time of the first use against the
       previous night's sleep is k.
     - **j. Hours after a use: this PR** (#187, `feat/insights-hours-after`). `lib/insights/hours_after.dart`: for each use
       with none of the habit in the 4 h before and every window ended by today's start, heart rate (and HRV) in 0-30,
       30-60, 60-120 and 120-240 min after, less the hour before. Heart rate climbs after waking whatever the clock
       says (review of the first version: same-clock controls gave Coffee-on-waking a false finding in 40 of 40
       whole-day reports, through BH), so moments are timed from waking: the time in bed comes from Health
       (`HealthSampleMetric.bed`, a new `samples` branch in `HealthChannel.swift` over `HealthDays.nights`, one call
       for the year, no new read type), a day's waking is the end of its longest span ending 18:00 the day before to
       15:00, and a moment needs a known waking before its hour before and no time in bed to its last window's end.
       The control is the same difference as long after waking on the nearest day within 7 whose waking is within
       2 h of the use day's (by clock), inside the habit's span and clear of it 4 h either side. So Coffee within an
       hour of waking, or anything within 4 h of bed, is refused in words; a day with no night recorded gives no
       moment (a Watch charged overnight gives no hours-after at all, and the page does not say why: the "needs your
       sleep" refusal exists, but with nothing planned the provider reads no heart rate and the engine skips the
       comparison; steps-based waking is the named fallback, not built). A window is dropped when another habit was used from its baseline to its end, the habit again before
       its end, under 3 readings in baseline or window, or a walk (any 10 min over 60 steps a minute in the
       baseline, or from 30 min before the window to its end); the change in steps a minute is a covariate.
       Moments are averaged per day, one OLS per window on days (intercept, use, steps); at least 10 days each side.
       Results join the page's Benjamini-Hochberg family. A too-few-days refusal names the cause that left out the
       most moments on the short side (few uses, no sleep recorded, near waking or bed, another habit, the habit
       again, readings, walks, no clear nearby days). Copy: "One to two hours after Coffee, your heart rate, set
       against the hour before, averages 6 bpm higher than at the same time after waking without it." Cost: the
       last 120 uses per habit in the last 365 days, one control each, one call for bed then one sample read a day
       per measure (heart rate, HRV, steps; `HealthSampleMetric.stepCount` added), the measures side by side, capped
       at 60 s; the page says so. The page shows the daily report while that runs ("Still reading heart rate ...")
       and recomputes when it lands, so a daily finding can then move to "could be chance". Synthetic year (Coffee,
       Tea, Water): 702 moments, 249 spans, 748 channel calls, 64,729 samples. `sleepingHeartRate` has copy ("heart
       rate while asleep", a night metric) but stays out of `healthStateProvider`'s read: its query holds up the
       whole read and its cost over a year of nights is unmeasured; measure on a device when adding it back. A
       `not-determined` sample read leaves hours-after out, not the page; the Health card's "Allow new Health data"
       (#184) offers the sheet. Measured (`tools/insights-calibration/hours_after_test.dart`, false or true findings
       per window before BH, 0-30 / 30-60 / 60-120 / 120-240): clock-tied morning climb, 400 seeds: noise 2.8 / 3.0 /
       1.5 / 1.0%; walk after 70% of Coffees 4.5 / 5.5 / 1.5 / 1.0%; +1 bpm at 60-120 found 56%, +3 bpm 100%; +1.5
       bpm at 0-30 over 60 days 80%. Whole days with sleep (heart rate 52 asleep, 62 plus a 10 bpm climb over 2 h
       after waking; weekday waking 06:30, weekend 08:30), 200 seeds: Coffee 15-60 min after waking 0 / 0 / 0 / 0%
       (refused near waking; 0 of 40 whole reports, from 40 of 40), Coffee 2-3 h after waking 1.0 / 3.5 / 2.5 / 1.0%,
       weekdays 07:00 2.0 / 1.0 / 0 / 0%, random 09:00-15:00 4.5 / 3.0 / 1.5 / 4.0%, heart rate every 10 min with 30%
       missing 4.0 / 3.0 / 3.0 / 3.0%, 30% of nights missing and 30% split 6.0 / 3.5 / 2.0 / 2.5%, beside Cigarettes
       8 a day 3.5 / 3.5 / 0 / 0%, Cigarettes 8 a day itself 0.5 / 0 / 0 / 0% (refused: no clear days, the habit
       again), bedtime Coffee refused; +3 bpm at 60-120 found 87% (2-3 h after waking) and 100% (random). Whole
       page on noise (9 day outcomes, Coffee, Tea, Water): hours-after raw 3.0% of 4,792 checks, 0.1% after BH; 8.5%
       of reports show any finding, 1.3% an hours-after one. Known limit, not fixed: a use timed by how the person
       feels (Coffee at the day's low point) gives 16 / 5.5 / 14 / 32.5% false findings (regression to the mean
       from a baseline picked low; the first version gave 12 / 7.5 / 7.5 / 18%); it needs another estimator, and the
       page note says so. Not run on a device: the bed read and the 748 calls' time, real Watch sampling density
       (synthetic is a reading every 5 min; the 3-reading gate may refuse sparser data), real sleep records
       (sources, naps, the 18:00-15:00 waking rule), iPhone and Watch step samples double-counted (errs toward
       dropping a moment). HRV at Watch density (a few a day) is refused for too few readings. With no step samples
       at all the walk guard and the steps covariate drop out.
     - **k. Before a use:** the reverse direction: last night's sleep, HRV and resting heart rate against the next
       day's use, and heart rate in the hour before an entry.
     - **l. One habit after another:** how often a habit follows another within minutes, against chance.
     - **m. Step changes:** a level shift in a measure (an illness, a new routine) found and modelled, so it is not
       pinned on a habit that began at the same time.
   - **Direction (Jack, 2026-11-09, "sounds good" to Claude's recommendation):** Insights becomes question-led, not a
     list of "days after X, Y differs" cards. Archived habits show no cards (they stay in the model as covariates).
     **Bedtime on sleep cards, decided (Jack, 2026-11-09): option 2.** Amount and time cards on sleep-minute metrics
     show the total effect as the headline, then a line with the part left at the same bedtime (for example "11 min
     less per hour later, 4 min of it at the same bedtime"). Rework #190 to show both, on top of #192's card lines.
     Build order after the steps in flight (j, the bedtime fix): **n. where's the line** (a dose threshold instead of
     one straight line, and a time cut-off), **o. recovery time** (nights until a measure returns to baseline after a
     heavy day), **p. payoff from cutting down** (measures since a habit fell, against the old baseline), **q.
     replacement** (one habit rising as another falls), then **k. triggers**, where calendar, places and daylight add
     most; plus a daily "last night against your usual". Page structure and where the daily check lives were pitched
     in round 12 (`docs/pitch/round-12/insights/`); **decided (Jack, 2026-11-09): 1A**, the Insights page as three
     question sections, **and 2C**, the last-night check in both places: Today shows sleeping heart rate alone and
     opens Insights, where the full check sits at the top.
   - **h. More sources** (Jack, 2026-11-08: "add them all to the roadmap";
     `ideas/insights/more-data-sources.md`): Health beyond sleep and heart rate, places, daylight, music, Reminders
     and Focus first; Journaling Suggestions, weather, Screen Time and spending carry the blockers in that file.

### Third run (`/finish-and-pitch`, 2026-11-09)

Usage: the all-models weekly limit stood at 98% with no overage, so every agent runs on Fable (its own budget) and
the run lands small items first. Stale in the lists below, checked 2026-11-09: D4 (#141), U1 (#155), U6 (#156), D16
(#153) and D2's pills, page fades and range morph (#147, #149, #150) are merged.

**Done, this run (2026-11-09):** T1 #190 (sleep cards: total, then the same-bedtime part), T2 #198 (Insights as
three question sections; last-night check on Today and at the top of Insights), T3 #197 (floors from the
literature, per person, with a source line per card; research in `docs/insights/floors-literature.md`), T4 #151
(macOS e2e in CI after merge; the job patches its copy of firebase-ios-sdk to the file keychain and forces Flutter
auth fields, so a green run proves screens and flows, not keychain sign-in or the native fields of the signed app),
T6 #199 (mini time dial in the amount sheet and editor; edited bead travels to its new time; the day word opens the
calendar), T7 #196 (firebase-data-layer class: the sealing migrator leaves an oversized legacy document in plaintext,
reported by path, instead of failing its batch; the unused vices index removed from the file, still live in
production since deploys never `--force`). T5: 18 `archive/*` tags pushed and verified; deleting the 18 remote
branches was refused by the permission check ("Git Destructive") and waits for Jack. #128 stays open while P2 is
unresolved. None of #197, #198 or #199 has run on a device.

**Calls waiting on Jack:** round 13, https://claude.ai/artifact/WvhfWBfk8xUfzqwHXpWzMF (source
`docs/pitch/round-13/`, picks in its `picks` collection): heart-rate floor, noise rule, active-energy floor, what
"your usual" means for last night, Today's last-night line copy, empty question sections, the time dial's day button,
the bedtime part in the false-discovery family, refusing plaintext creates, entries of deleted habits, the API key
restrictions.

**Blocked:** D9 (switching this Mac's Flutter while agents build), D11 (Flutter 3.47 not yet pinned), B1 to B6, the
branch deletions above.

### Overnight run (`/finish-and-pitch`, 2026-11-08)

Open work on 2026-11-08: `origin/master` at 82f69f0, open PRs, remote branches, CI on `master`, register, backlog.
Effort: S under a day, M a day or two, L more.

**In progress, owned by other agents (leave alone):**

- **P1.** DONE (#133, merged 2026-11-08): native AppKit auth fields on macOS for Passwords AutoFill, less clunky
  (`feat/mac-native-auth-fields`).
- **P2.** Why the journal key did not sync iPhone to Mac via iCloud Keychain: under investigation on
  `fix/journal-key-sync` (not on `origin` at the inventory).
- **P3.** Mac fullscreen layout pitch, 3 options: `design/mac-fullscreen-a` pushed; b and c local worktrees.

**DECIDED** (goal set by a recorded call or a convention):

- **D1.** DONE (#148, merged 2026-11-08; 1b and 1d leftover): the amount sheet (title, stepper, pill button) replaces
  the record dialog for new entries; the editor page builds the same `AmountFields`. Follow-ups: a mini time dial
  replacing `ActivityDateField`, as mocked (next; D2's edited bead travel needs it); a step of 5 for habits whose
  typical entry is 10+; the editor as the sheet, not a page (with D5, which rewrites the editor e2e flows).
  `lib/widgets/`. M.
- **D2.** The rest of 1f (#98's "Left for 1f"): `animations` page transitions, `OpenContainer` for a Trends day point,
  chart morph between ranges, offline and refused-write pills on a spring, an edited bead travelling to its new time
  (needs D1), reduce-motion day fade, dial drag snap-back. `lib/widgets/`. L.
- **D3.** DONE (#146 from `feat/dense-hour-arc`, merged 2026-11-08; stills in `docs/pitch/dense-hour/`; 1b leftover).
  Above 48 entries a day, a multi-entry hour is one arc; a lone entry stays a bead, pushed clear of arcs. Arcs draw no
  pending rim for unsynced entries (register, `dense-hour-arc-shows-no-pending-entries`). `lib/widgets/day_dial.dart`.
  S.
- **D4.** The history page's "Last 30 days" summary card (1d leftover). History page. S.
- **D5.** DONE (#145 from `feat/e2e-1g-mac-window`, merged 2026-11-08). Rest of 1g: `integration_test/` rebuilt around
  fan gestures, dial semantics and sheets, on iOS and `E2E_DEVICE=macos` (#119 did the finders and one-build suite):
  `log_fan_test.dart` (press-drag-release onto a wedge, release off the fan, Escape, Log's screen-reader actions, a
  wedge's tap and hold via semantics); Trends helpers and checks follow the sheet or split pane. Follow-ups: amount
  sheet tests wait on D1; the macOS suite on the split view is unproven until D6 or a hand run of `E2E_DEVICE=macos
  tools/e2e.sh`. `integration_test/`. M.
- **D6.** macOS e2e in CI after merge, beside iOS (`e2e.yml` runs iOS only; C10 puts e2e in CI; `r2-mac` ships the Mac
  only if its e2e is green). `.github/workflows/e2e.yml`. M.
- **D7.** DONE (#145, merged 2026-11-08): #108 (`r8-mac-window` B, 1200 x 780) carried onto #145 without its 800 x 600
  test override; #108 closed. `macos/Runner/MainFlutterWindow.swift`. S.
- **D8.** Queue item 6: widgets, Control Centre controls, Mac menu bar app; signing check done (proven on iOS; macOS
  App Group naming unchecked). New native targets. L.
- **D9.** `flutter build macos --release` (universal) fails here at Flutter's architecture check; workaround:
  xcodebuild `ARCHS=arm64`. Under Xcode 27 it needs Flutter 3.44.8+ (flutter/flutter#188346, Xcode 27's `lipo`); CI
  pins 3.44.9, last passed 2026-11-05. That Homebrew Flutter 3.44.7 here is the cause is inferred, unverified. 3.44.9
  is at `~/development/tracker-tools/flutter-3.44.9`: switch to it while no agent builds, then rebuild. Machine setup.
  S.
- **D10.** DONE (#136, merged 2026-11-08): `tools/build-version.sh` runs the build command given (`release` skill).
- **D11.** Flutter 3.47 (Dart 3.13) and riverpod_lint 3.1.9, the separate step in `CLAUDE.md`.
  `.github/actions/setup-flutter/action.yml`, `analysis_options.yaml`. M.
- **D12.** DONE (#139, merged 2026-11-08): closed register entries Jack's calls settled or that no longer held:
  `activity-timestamps-come-from-the-device-clock` (`r4-server-time`: as built), `vice-lists-are-unbounded`
  (`r4-vice-cap`: no cap for 1.0), `no-email-verification` (`r3-verify`), `every-firebase-command-targets-production`
  (`r2-testflight`: no beta project). `rules-and-indexes-are-never-deployed-or-tested` stays (re-checked: CI deploys,
  #90 checks the index file); console drift and the unused `archived` index are unchecked. `tech-debt/`. S.
- **D13.** DONE (merged 2026-11-08), one class per PR: generated plugin registrant tracked on macOS only (#137),
  duplicated client API key (#138), template tests (#140), e2e record helper flake (#142). `tech-debt/`.
- **D14.** DONE (#139, merged 2026-11-08): `ideas/` refreshed. "Needs Jack" drops the calls Jack has made (E2EE, age,
  Mac, Pro, billing, TestFlight, icon, guests, check-in, presets, triggers, Today, app lock); idea files for shipped
  work (`end-to-end-encryption`, `one-tap-quick-logging`, `trigger-tagging`, `granular-logging-and-data-model`, part
  of `guest-mode-and-sign-in`) deleted or trimmed. The E2EE file's open items moved to
  `tech-debt/firebase-data-layer/` (sealed-only rules, binding scope and key rotation, migrator edge cases),
  `tech-debt/auth-and-account-lifecycle/` (clipboard), the release-pipeline idea (export compliance) and the privacy
  idea (Crashlytics scrubbing).
- **D15.** Close draft #128 (keychain probe, CONFLICTING, "not for merge") once P2 no longer needs it. S.
- **D16.** Reduce motion row in Settings (`r10-reduce-motion` B, round 10): Follow system / Reduce / Full. PR #153
  (`feat/reduce-motion-setting`). Full can't restore framework-scaled motion: with iOS Reduce Motion on, every default
  `AnimationController` runs at 5% length and no release-mode API turns that off. So Full covers the app's own
  controllers (`AnimationBehavior.preserve`: dial, log fan, tallies, day picker, Undo timer, status pills
  (`PillDrop`), the Trends range morph (`RangeMorph`)) and pushed pages (`DialPageRoute`); sheets, dialogs and
  implicit animations (segment thumbs, label fades) follow the system, as the page's foot copy says. Open: a custom
  `WidgetsFlutterBinding` overriding `SemanticsBinding.disableAnimations` would cover the rest (inferred, untested).

**Were UNDECIDED; all decided in round 10 (2026-11-08)** (U1 to U8; picks in Jack's calls, round 10):

- **U1.** Mac fullscreen layout (P3's options): `r10-mac-fullscreen` B. M.
- **U2.** Queue item 6's questions (what "top" habits means, Undo after a widget or menu bar tap, Siri, Shortcuts and
  the Action button via one App Intent, macOS desktop widgets from the same code): `r10-widget-top` D,
  `r10-widget-undo` B, `r10-intents` A, `r10-mac-widgets` A; queue item 6 holds them.
- **U3.** Reduce motion row in Settings, as mocked: `r10-reduce-motion` B (D16). S.
- **U4.** Other languages: `r10-languages` A, English only. No work.
- **U5.** Content-free analytics beyond Crashlytics (`ideas/v1-must-haves/crash-reporting-and-analytics.md` defers it
  to 1.1): `r10-analytics` A, none. No work.
- **U6.** Reminders (`r2-days` ruled out the daily check-in, not reminders;
  `ideas/v1-must-haves/evening-check-in-and-reminders.md`): `r10-reminders` B, one optional daily nudge. M.
- **U7.** Pushed pitch-source branches with no PR: `r10-pitch-branches` C. The Day Dial files landed in the
  `docs/round-10-picks` PR; archive tags and branch deletions fall to the main session after it merges. S.
- **U8.** When to cut 0.2.0 and install on Jack's iPhone and Mac: `r10-release` B, wait. S.

**BLOCKED on Jack** (tasks, not decisions; detail under For Jack to do):

- **B1.** Read `dailyOrphanCleanup`'s dry-run logs for a few days; then Claude pitches the `DELETE_ORPHANED_DATA`
  flip. S.
- **B2.** The paid Apple Developer team: Jack is not getting it for now.
- **B3.** Waits on a release: domain, support and legal pages, privacy-policy details, an App Store search.
- **B4.** The main checkout's modified `macos/Runner.xcodeproj/project.pbxproj`: discard or keep.
- **B5.** Delete the old `com.screendead.tracker.tracker` install, then its two iOS registrations in the console.
- **B6.** Optional: Cloud Scheduler "Force run" on the monthly summaries job, to fill them before the 1st.

**CI on `master`:** last finished e2e run green (a2b5c30, #130); 82f69f0's (#132, #134) still running at writing. The
one red run, fef30f9 (#116, 2026-11-07), was followed by green ones. The 2026-11-07 Dependabot failures (functions'
minimatch and glob) predate #120; no alerts open. Skipped tests: fidelity renders (skip without an output directory)
and DST guards (skip in a zone without DST; CI sets `TZ=Europe/London`); none by mistake.

### This run (`/finish-and-pitch`, second pass, started 2026-11-06)

Closed: every track below, the first pass (waves A to D) and #83, merged 2026-11-06/07. CI was down 2026-11-06
(Actions billing limit) until Jack made the repo public and renamed it `Screendead/penchant` that day.

**DECIDED** (in order; code PRs stacked, to merge once CI was back or Jack waived it):

- **Track A, the overhaul, stacked on #83:** 1c Trends sheet, then 2 macOS split view, then 1d Habits/history/editor
  (amount sheet, swipe-to-delete with Undo, settling the register's inconsistent-delete item), 1e auth and settings
  (keyboard focus on list rows, navigation destinations and the slider, which #82 found at about 1.2:1), 1f motion
  polish, 1g e2e rewrite. One PR each, stacked.
- **Track B, Apple platform debt, off `master`:** done. CocoaPods sunset (`chore/swift-package-manager`: both
  platforms on Swift Package Manager, no Podfile left); the failing `flutter build macos --release`, legacy signing
  config and dead scaffold assets (`chore/apple-build-config`, stacked on #87). Flutter version: D9; 3.47: D11.
- **Track C, reliability and tooling, off `master`:** a refused write queued by an earlier launch was dropped silently
  (#88, `fix/rejected-write-earlier-launch`, reviewed: a device journal checked on the next launch); the minimatch
  override broke firebase-tools glob paths, and nothing checked the index file against the queries (both #90,
  `chore/minimatch-and-index-check`, stacked on #88: a range-keyed override and `test/firestore_indexes_test.dart`; no
  app change, so no e2e).
- **Docs:** land `design/day-dial-system` (the published design system's sources) on `master`.

**UNDECIDED:** none then: round 9 picked 2026-11-07, every earlier call 2026-11-06; `r7-ci` and round 5 moot. Other
languages, then unasked, were decided in round 10 (U4).

**Blocked on Jack:** the paid Apple team and the release (B2, B3).

Housekeeping rides with whatever PR touches it: deleting fixed tech-debt and shipped idea files with their README
lines, and the recount (`tech-debt/README.md`).

## Jack's calls, round 1 (2026-11-03)

Picked on the pitch page, which keeps the options and costs.

- **C1. Rules deployment** (`rules-deploy`): **CI deploys rules and indexes on merge to `master`.** On since
  2026-11-04; rule in `CLAUDE.md`.
- **C2. Today with 1 or 2 vices** (`today-few-vices`): **bars below 3 vices, the radar from 3 up.** Superseded by
  `r6-ui-direction` (round 6).
- **C3. Save timeout** (`record-timeout`): **close the dialog and say the entry will sync.**
- **C4. Undo duration** (`undo-duration`): **8 seconds.**
- **C5. Clean day** (`clean-day`): **quietly positive**: green tint, short encouraging copy, no streak pressure.
- **C6. Platforms** (`platforms`): **iOS first, through TestFlight.** "Delete the rest. Add a MacOS target too,
  fully-supported." Android and web go.
- **C7. `functions/`** (`functions`): **delete it** and close its Dependabot PRs. Back for `r8-bead-size`
  (2026-11-06, below).
- **C8. Licence** (`licence`): **proprietary, all rights reserved.**
- **C9. Stale git state** (`git-cleanup`): **archive the stashes, then clean**; keep `copilot/fix-9`.
- **C10. E2E in CI** (`e2e-ci`): **in CI on `master` after merge, debounced** (Jack, 2026-11-06, superseding "local
  only"; `e2e.yml`, #96). Rule in `CLAUDE.md`.
- **C11. PR previews** (`pr-previews`): **drop them.** Moot once web goes (C6).
- **C12. Quantity** (`quantity`): **greater than 0** on a new activity, so a free day isn't a zero entry.
- **C13. Vice name length** (`name-length`): **60 characters at most.**
- **C14. Vice ownership** (`vice-owner`): **check it**: an activity's vice must belong to its logger.
- **C15. Positioning** (`positioning`): **a neutral journal, for seeing trends and learning about yourself.** Jack's
  note, condensed: strengthen the journal and trends significantly; cutting down may coexist, but the journal is the
  point. Wanted, as intelligent insights: what causes use (calendar meetings; triggers from options that narrow as
  you click, remembering your most common, or free text) and what follows from one vice against another (Apple
  Health: sleep, HRV, heart rate and the like, history included, disambiguating which vice a health effect
  correlates with over time). Maximum granularity. Privacy is fine while sensitive processing and storage stay on
  the device; all of it regenerates from the raw data.
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer. Now 18+ (`r2-age`, below).
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes**, optional or, with a first-launch migrator, mandatory; rule
  in `CLAUDE.md`.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** Penchant (`r2-brand`, round 2).

## Jack's calls, round 2

- **`r2-web-site`** (2026-11-03, in chat): **take the live web site down now.** Firebase Hosting on the production
  project is outside Claude's reach under the hard rules, so Jack did it; 404 since (checked 2026-11-04). Done.
- **`r2-icon`** (2026-11-05, in chat): **candidate 38** of 38 on the icon sheet
  (https://claude.ai/artifact/JGnHCcPxaTLHKiyZeFgNmK, sources on tag `archive/mockup/icon-sheet`): the Today radar's
  coloured segments, spokes running past them, centred on a light background. Shipped as the iOS and macOS icon
  (`assets/icon.svg`, `assets/icon-macos.svg`) in the PR recording this. Independent of the brand. Done.
- **`r2-brand`** (2026-11-05, on https://claude.ai/artifact/NBsbWYMVPh2phzS3wKDRCH, no note): **Penchant**, with the
  recommended App Store subtitle **"Habit journal & sleep insights"**. Identity strings in #81, bundle IDs in #84.
  Backups if unusable: Kenning, then Sounding. Settles C19. **`r2-brand-icon`** (2026-11-06): "We
  already have a brand I like": the icon stays candidate 38. Mock-up habit names are made up; "Tracker" there is a
  placeholder.
- **`r2-presets`** (2026-11-06): **A, the plain names** (Alcohol, Coffee, Cigarettes, Vape, Cannabis, Energy drinks,
  Sweets, Gambling) in a first run for an account with no habits: intro, presets plus "Something else", the
  disclaimer, an optional first log. Built from `feat/onboarding-presets` (`lib/onboarding/`).
- **`r2-mac-config`** (2026-11-05): the Mac shares the iOS app's Firebase registration and config file
  (recommended; `CLAUDE.md`).
- **No trademark search** (2026-11-05, Jack): none, professional or otherwise. Don't raise it again.
- **Wording** (2026-11-05, Jack, #81): the UI says **"habits"**, not "vices"; code and data keep `vice` (`CLAUDE.md`).

## Jack's calls, round 6

- **`r6-ui-direction`** (2026-11-05, from the `picks` collection of the UI overhaul pitch page
  https://claude.ai/artifact/23uvjtPyS7TqPvXaEBw9Px): **Day Dial**, the day as a 24-hour dial, each entry a coloured
  bead at its time. Settles **`r2-today`** (A, the journal layout, superseded); supersedes C2 (`today-few-vices`):
  radar and bars left Today in #83, mooting round 5 (`r5-radar-inset`, `r5-key-height`, `r5-key-always`). Allows
  the one-tap **"log one"** (`CLAUDE.md`). Chrome is ink on paper; the five icon colours mean habits only, assigned
  by creation order on the device, no stored field (scheme in `CLAUDE.md`). Units stay the existing enum; new units
  are `r2-data-model`. Built as queue item 1.
- **Contrast** (2026-11-05, in chat): **every colour pair meets WCAG 2.2 AA in both themes**: 4.5:1 for text, 3:1 for
  icons, meaningful graphics, control edges and focus. Fix, never flag; habit colours keep the icon's five hues
  (lightness, rims and inks may change). Pairs in `docs/design-system/day-dial/project/contrast-pairs.json`, checked
  by `tools/contrast-check.py` and `test/contrast_test.dart`; a new colour use adds its pair. One exception:
  `r8-clear-spokes` (2026-11-06, below).

## Jack's calls, rounds 2 to 4 and 8 (2026-11-06)

Picked on https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs, which keeps the options and costs. Notes are Jack's,
condensed. `r2-presets`, `r2-brand`, `r2-brand-icon`: round 2; `r2-today`: round 6.

- **`r2-privacy`**: **no privacy policy for now.** Penchant is for Jack's own use ("I'm not actually going to put it
  on the App Store; it's just for me"): production polish, but store, legal and payment work (privacy-policy
  details, App Store listing, Pro and billing, TestFlight) waits until and unless he decides to sell.
- **No paid Apple Developer account for now** (Jack, 2026-11-06). What waits on it: For Jack to do.
- **`r2-testflight`**: **Production** (no separate beta project). "Just Do It Right." Moot until a paid team.
- **`r2-signin`**: **guest start, link an account later, plus Sign in with Apple.** Jack's production data, under an
  email-and-password account, must end up on his Apple ID; linking the Apple credential to that user keeps the uid,
  so no data copy. Sign in with Apple needs the paid team; guest start and email linking don't.
- **`r2-e2ee`**: **yes, before 1.0**: names, units, amounts and later notes sealed on the device (AES-256-GCM); dates,
  IDs and owner stay plaintext. Key in iCloud Keychain plus a printable recovery key. Amounts stay plaintext after
  all (Jack, 2026-11-06, for `r8-bead-size`); `CLAUDE.md` lists the sealed fields.
- **`r2-e2ee-key`**: **a Today card after a week; Settings any time.**
- **`r2-data-model`**: **optional fields, plus a first-launch migrator (for a vice category) and a decimal amount**
  next to the whole-number quantity.
- **`r2-days`**: no option picked; the call: **a day with nothing logged is clean.** No check-in, no days collection.
- **`r2-triggers`**: **Areas of life** (Social, Feeling, Work, Body, Routine, Place, Craving), against the
  recommended B.
- **`r2-age`**: **18+** (Apple retired 17+ in July 2025, superseding C16's "17+"); neutral framing, disclaimer
  (C16). **`r2-mac`**: **the Mac ships with iOS 1.0 if its e2e is green.** Both moot until a release.
- **`r2-pro`**: **the analysis layer, $24.99**. **`r2-billing`**: **StoreKit 2 directly.** **`r2-applock`**: **app
  lock and discreet mode both free.** Parked with the store work.
- **`r2-crash`**: **Crashlytics only.**
- **`r2-cli`**: **upgrade the global Firebase CLI** (`npm install -g firebase-tools@latest`).
- **`r3-delete-copy`**: **ship the deletion wording as written.** **`r3-verify`**: **nothing requires a verified
  email.** **`r3-cache`**: **keep the on-device cache.** **`r3-attest`**: **App Attest with DeviceCheck fallback, as
  built.** All as built; no work.
- **`r4-server-time`**: **the phone's clock, as built.** **`r4-vice-cap`**: **no cap for 1.0.** No work.
- **`r4-weekly`**: **round the range down to whole weeks** (30 days shows 28), against the recommended A. Built (queue
  item 4).
- **`r8-clear-spokes`**: **25%, as the mock-up**, against the recommended A: on a clear day the major spokes are
  decoration (the 00/06/12/18 labels give the time), classed so in `contrast-pairs.json`, a contrast-rule exception
  for that state only. Built (queue item 4).
- **`r8-coach`**: **don't build the "Tap Log" pill.**
- **`r8-bead-size`**: C, **a typical amount stored per habit**, on Jack's terms: not editable, computed monthly by a
  scheduled job over the last 3 months only. Generally, precompute per-user reads into one document per user
  wherever possible, cutting reads and load times, above all for graph and calendar. Runs as **a Cloud
  Function** (Jack, 2026-11-06, over the app refreshing the document). Built as `monthlySummaries` from
  `feat/bead-summary-function`.
- **`r8-tally-target`**: **44 x 38, as built.**
- **`r8-mac-window`**: **about 1200 x 780, the split view by default.** Built with 1g in #145 (D7).
- **`r8-mac-keys`**: **Cmd-1 to Cmd-9 log one of the Nth habit now**, listed in the menu bar. Built (queue item 4).

## Jack's calls, round 9 (2026-11-07)

Each as recommended on the pitch page:

- **`r9-archive`**: A, **the archive button on the habit's history page, as built.**
- **`r9-appearance`**: B, **a Match system / Light / Dark choice, saved per device** with shared_preferences (no
  data-model or rules change). Built from `feat/r9-picks`.
- **`r9-export`**: B, **also an Export row in Settings, as the mock-up**; Account Settings keeps its row beside
  Delete; both share one export action. Built from `feat/r9-picks`.

## Jack's calls, round 10 (2026-11-08)

Picked on the round 10 pitch page (`docs/pitch/round-10/`). All but `r10-mac-widgets` match
Claude's recommendation (B, later). Notes are Jack's.

- **`r10-mac-fullscreen`**: B, **responsive scaling**: both panes grow with the window, the dial with the height.
  With Claude's two pitch conditions: cap the dial near 480 pt; keep Today's column at
  504 pt at 1200 x 780. Built from `design/mac-fullscreen-b` (tag `archive/design/mac-fullscreen-b` once archived;
  U1).
- **`r10-widget-top`**: D, **top habits = most logged in the last 30 days, overridable in the widget's settings.**
- **`r10-widget-undo`**: B, **a 5-second Undo where you tapped**, on each surface (widget, control, menu bar row). If
  WidgetKit can't hold and revert that state, Claude falls back to C (the app's Undo on the Mac menu bar only) and
  says so.
- **`r10-intents`**: A, **Siri, Shortcuts and the Action button through the same log intent**, built with the widgets.
- **`r10-mac-widgets`**: A, **macOS widgets from the same code**: the WidgetKit code as a Mac extension, built with
  the iPhone widgets, for the desktop and Notification Centre. Depends on the journal key reaching the Mac (P2).
  Jack: "Widgets for the Notification Centre are useful to me."
- **Mac menu bar after quit** (2026-11-08): Jack: "the menu bar app should still be present even when the app is
  cmd+q'd too." Built as a login-item helper (queue item 6); a hidden flush-mode launch writes a log made with the
  app closed within seconds (PR #167).
- **`r10-reduce-motion`**: B, **a Follow system / Reduce / Full row in Settings, saved per device** in
  shared_preferences like Appearance. PR #153 (`feat/reduce-motion-setting`): Full covers only the app's own
  controllers and pushed pages, since iOS Reduce Motion scales default controllers to 5% and no release-mode API
  turns that off (D16).
- **`r10-languages`**: A, **English only** (register: `no-localizations-delegates-or-supported-locales`).
- **`r10-analytics`**: A, **none** beyond Crashlytics.
- **`r10-reminders`**: B, **one optional daily nudge**, off by default. Jack: a long press should offer something like
  "Nothing further" or "Clean day"; it needn't do anything, but should feel good to press.
- **`r10-pitch-branches`**: C, **land the Day Dial mock-up files, tag the rest as `archive/*`, then delete those
  branches.** Files in `docs/pitch/mockups/ui-overhaul/day-dial/`; every other pushed pitch-source branch with no PR
  (`mockup/*`, `design/ui-overhaul-*`, `design/mac-fullscreen-*`, `spike/*`) is tagged `archive/<branch>`. The main
  session runs the tag and delete commands, in the PR from `docs/round-10-picks`, after it merges.
- **`r10-release`**: B, **wait**: cut 0.2.0 once the picked Mac fullscreen layout and PR #133 (AutoFill) land, then
  install it on Jack's iPhone and Mac. Its first launch runs the sealing migrator over his real journal.

Later that day, in chat, on the widgets (#158) and the nudge (#156):

- **Background refresh, battery-light.** Jack: "Background refresh now. Don't use up all of my phone's battery with
  it." A widget, control or Siri log reaches Firestore without opening the app; no polling, no silent push. Built in
  #158, both only while logs are queued: on iOS a system-timed `BGAppRefreshTask`; on the Mac, while the app runs, a
  retry every 15 minutes or more at utility priority. Since reworked (PR #166, PR #167, `r11-ios-widget-sync` B);
  current mechanism: queue item 6.
- **Plaintext habit names and counts in the App Group are acceptable.** The widgets' snapshot and queue stay
  as built in #158 (cleared on sign-out).
- **The Lock Screen shows the top 3**, as built in #158.
- **The daily nudge fires every day regardless**, even on a logged day. Jack: "in case something was missed".
  **"Clean day" just dismisses** (option c). Both as built in #156.
- **Log widget = Hero with Glow** (Jack 2026-11-08: "B, with C's glow"). The first habit is a dial with a + badge,
  the rest pills with their count and a + button, each on a soft glow of its colour. Renders in
  `docs/pitch/round-11/log-widgets/final/`.

- **Insights: how steep a change in use is refused** (Jack, 2026-11-09: **C**, against the recommended A). Built in
  #183, merged into #181: a level per calendar month plus the trend; from two periods on, the only balance refusal
  is fewer than 2 months with days both with and without the habit; a span of one period keeps #181's halves guard.
  Cut-downs with a real effect are found (80% to 25%: 198/200); the cost is a change in use and a step in the outcome
  inside one month (34/200 false findings against A's 13 on the bench). The measured table is in #183's PR body.

## Calls waiting on Jack (UNDECIDED)

None on the pitch page. Every call is picked: rounds 1 to 4, 6 and 8 on 2026-11-03/05/06, round 9 on 2026-11-07, and
round 10, which decided U1 to U8 in the overnight list (Jack's calls, round 10, above), on 2026-11-08. Round 5 and
`r7-ci` are moot. One call is open off the pitch page:

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
- **Functions deploy setup, done; for the record:** (1) `screendead-vice-tracker` on the Blaze plan; (2) the Cloud
  Functions, Cloud Build, Artifact Registry, Cloud Scheduler, Cloud Run, Eventarc and Pub/Sub APIs enabled; (3) the
  deploy service account (then Firebase Rules Admin, Cloud Datastore Index Admin, Service Usage Consumer) granted
  `roles/cloudfunctions.admin`, `roles/iam.serviceAccountUser` on the default compute service account,
  `roles/cloudscheduler.admin` and `roles/artifactregistry.admin` (for the CLI's image cleanup policy; or run
  `firebase functions:artifacts:setpolicy` once); (4) `DEPLOY_FUNCTIONS=true`; (5) the Cloud Functions workflow
  re-run on `master`. A deploy names any permission still missing.
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
