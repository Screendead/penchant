# Handover — Tracker

*Updated 2026-11-03. Audience: the next agent, or Jack. This file holds the current task: the queue, where each item
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
| Standing rules (production safety, e2e gate, merge authority) | Merged 2026-11-02 (#24) | `CLAUDE.md` |
| CI checks: analyze and test on every PR; live deploy waits on them | Merged 2026-11-02 (#25) | `.github/workflows/checks.yml` |
| Emulator wiring and iOS end-to-end harness | Merged 2026-11-02 (#29) | `tools/e2e.sh`, `lib/firebase_init.dart` |
| Firestore rules rewrite, 55 rules tests, missing index | Merged 2026-11-02 (#27); **deployed to production by Jack 2026-11-03** | `firestore.rules`, `tests/firestore-rules/` |
| Product ideas backlog | Merged 2026-11-02 (#26); being reworked for the journal positioning (queue 1d) | `ideas/README.md` |
| Recovered features (day navigation, history, editor, usage graph, Undo) and the fixes for Jack's two reported bugs | Merged 2026-11-03 (#28), e2e 4/4 after the rules deploy; live for users | `lib/` |
| Jack's 19 calls | Picked 2026-11-03; recorded below | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Tech-debt register | 135 issues (from 162 on 2026-08-11) | `tech-debt/README.md` |

Baseline on master, measured 2026-11-03 on Flutter 3.44.7: `flutter analyze` clean, `flutter test` 17/17, rules
tests 55/55, `tools/e2e.sh` 4/4. `dart run custom_lint` loads no rules (see the register). Re-measure; don't trust
this.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's calls below. Work it top down; skip what is blocked
and say so. Items under one number can run in parallel in separate worktrees; only one agent at a time runs
`tools/e2e.sh` or uses the default emulator ports.

1. **Wave 3: apply Jack's calls of 2026-11-03.**
   - **1a. Today and recording** (C2–C5): bars below 3 vices and the radar from 3 up; Undo stays 8 seconds; a clean
     day looks quietly positive; a timed-out save closes the dialog and says it will sync. Also register what wave 1
     found (non-prescriptive): the usage graph's curve dips below zero around a single spike, its y-axis repeats "1"
     and its last two date labels overlap; pages opened from the drawer leave the drawer open; `tools/e2e.sh`'s Add
     Vice save timed out in 2 of 23 early runs (cause unconfirmed). Uses the simulator.
   - **1b. Rules details** (C12–C14): a new activity's quantity must be greater than 0; a vice name is at most 60
     characters; an activity's vice must belong to its owner. Each with rules tests, and with the app's own forms
     refusing the same input first, so users see a message and never a permission error.
   - **1c. Repo and platform cleanup** (C1, C6–C11): delete `functions/` and close its Dependabot PRs; delete
     `android/` and `web/` and the hosting workflows (no PR previews); add a proprietary LICENSE; archive the two
     stashes as commits on a local `archive/stashes` branch, then drop them, and delete merged branches (keep
     `copilot/fix-9`); CI deploys rules and indexes on merge to `master` after the checks and rules tests pass (needs
     Jack's role grant, below). Retire register entries for code that no longer exists.
   - **1d. Rework `ideas/` for the journal positioning** (C15–C19): rewrite the backlog around a neutral journal
     with insights (see C15). Mark each decided idea as decided, drop what the calls rejected, add the insight ideas
     Jack named, and add a naming pitch with brand candidates for C19. Docs only.
2. **macOS as a fully supported target** (C6's note), after 1a and 1c: builds, runs against the emulators, its own
   e2e run, CI covers it. Registering a macOS app in the Firebase console is a production action: Jack's.
3. **Wave 2: the remaining critical and high tech debt** that touches the app, one class per worktree:
   - `error-handling-and-observability/`: bootstrap failure, AsyncValue error states, sign-up errors;
   - `widget-state-and-view-logic/`: the previous user's data showing after sign-out, and the write layer;
   - `offline-and-write-reliability/`: persistence, timeouts, pending states on deletes;
   - `navigation-and-unreachable-ui/`: the routes that dead-end on 404 (Manage Data's Edit is one);
   - `auth-and-account-lifecycle/`: password reset, re-authentication;
   - `accessibility-and-localization/`: chart semantics, the record dialog at large text sizes.
   Classes that touch the same files go in sequence, not in parallel.
4. **The reworked `ideas/` roadmap** (from 1d), items marked "Needs Jack: no", in the order its README gives.
5. **The rest of the register**, medium then low, one class per PR.

Housekeeping that rides along with whatever PR touches it: delete each tech-debt file a PR fixes, and each idea file
a PR ships, with its README line; run `tools/tech-debt-recount.py` to fix the counts. It resolves paths from its own
location, so run the copy inside the worktree you are changing.

## Jack's calls (2026-11-03)

Picked on the pitch page; the page keeps the options and costs each was chosen from.

- **C1. Rules deployment** (`rules-deploy`): **CI deploys rules and indexes on merge to `master`.** So every rules PR
  Claude merges reaches production; the rules tests gate it.
- **C2. Today with 1 or 2 vices** (`today-few-vices`): **bars below 3 vices, the radar from 3 up.**
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
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer.
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes.** Optional fields are fine. Mandatory fields are allowed too,
  but only with a migrator that runs on first launch and adds them to existing records.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** The brand itself is not chosen yet: 1d
  pitches candidates.

## Calls waiting on Jack (UNDECIDED)

- **The live web site.** Deleting `web/` (C6) stops deploys, but the site keeps serving its last build against
  production until hosting is disabled (`firebase hosting:disable --project screendead-vice-tracker`, Jack's to run).
  Keep it up until iOS ships, or take it down now?
- **The brand name** (C19): pitched by 1d.
- **The global Firebase CLI**: upgrade from 15.8.0 (15.34 is current)? Another project shares its emulator files.

## For Jack to do (not decisions)

- **Let CI deploy rules (C1):** grant the GitHub Actions service account (the one behind the
  `FIREBASE_SERVICE_ACCOUNT_SCREENDEAD_VICE_TRACKER` secret) the roles the rules and index deploy needs. 1c's PR names
  the exact roles from the Firebase docs. Until then the deploy job fails and rules changes still need your manual
  deploy.

## How to test here

- **Never against production.** Emulators run with `--project demo-tracker`; see `CLAUDE.md` "Hard rules".
- `tools/e2e.sh` runs `integration_test/` on an iOS Simulator (an "iPhone 18 Pro", or `$E2E_DEVICE`) against the
  Auth and Firestore emulators. `tools/run-emulated.sh` launches the app against them for a manual look.
- `npm --prefix tests/firestore-rules test` runs the rules suite; CI runs it on every PR.
- Only one agent at a time may use the simulator and the default emulator ports. Parallel agents that need an
  emulator use other ports (Firestore 8180, hub 4410, logging 4510, UI off) through a config outside the repo.
- `flutter pub get` rewrites `macos/Flutter/GeneratedPluginRegistrant.swift`; revert it, don't commit it (in the
  register).
- Read the Firebase documentation before any change to rules, indexes, queries or emulator wiring, and cite it in
  the PR.

## Where the backlogs are

- `tech-debt/README.md` — what is wrong, by class and severity. Non-prescriptive; the fix is the PR's to design.
- `ideas/README.md` — what to build next, as pitches with a recommendation each, ordered as a roadmap to a paid
  release. Items marked "Needs Jack: yes" go to him as pitches before they are built.

## Thoughts

- The app is a small Flutter + Firestore codebase (about 3,000 lines in `lib/`). Tests now exist at three levels
  (55 rules tests, 17 unit and widget tests, 4 e2e tests), but most of the app is still untested. Most of the work before release is making it trustworthy, not adding screens.
- Writes are inline `FirebaseFirestore.instance` calls in widgets. A thin repository layer would make the write paths
  testable without the emulator; it is in the register as debt, not yet a decision.

## Set aside, with reasons

- **Rebasing or force-pushing the recovered feature branch** to tidy its history: it was already pushed, and
  force-pushing needs Jack. It merges `master` in instead.
