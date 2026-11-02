# Handover — Tracker

*Updated 2026-11-02. Audience: the next agent, or Jack. This file holds the current task: the queue, where each item
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
| Recovered feature work (day navigation, history, editor, usage graph, undo) | Committed 2026-11-02; PR open, waiting on its end-to-end run | `feat/day-navigation-history-graph` |
| Standing rules (production safety, e2e gate, merge authority) | Written 2026-11-02 | `CLAUDE.md` |
| Emulator wiring and iOS end-to-end harness | In progress (wave 1) | `feat/emulator-e2e` |
| Firestore rules fix (Undo's permission-denied) and rules tests | In progress (wave 1); **not deployed to production** — see J1 | `fix/firestore-rules` |
| CI quality gates (analyze, test) | In progress (wave 1) | `ci/quality-gates` |
| Product ideas backlog | In progress (wave 1) | `docs/ideas` → `ideas/` |
| Tech-debt register | 162 issues catalogued 2026-08-11, burning down | `tech-debt/README.md` |

Baseline, measured 2026-11-02 on Flutter 3.44.7: after `flutter pub get`, `flutter analyze` reports 2 infos and no
errors, `dart run custom_lint` reports nothing because it loads no rules (see the register's
custom-lint-plugin-cannot-load-riverpod-lint entry), and `flutter test` passes its one smoke test. Re-measure; don't trust this.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's standing calls. Work it top down. Items on one line
of the same number can run in parallel in separate worktrees.

1. **Land wave 1.** Merge in this order, each after CI passes and (for app-behaviour changes) an end-to-end run on
   the iOS Simulator against the emulators: `feat/emulator-e2e` → `fix/firestore-rules` → `ci/quality-gates` →
   `feat/day-navigation-history-graph` (merge `master` into it first; never rebase a pushed branch). Before the
   last one merges, add integration tests for the two bugs Jack reported: the day picker's back/forward and dropdown
   change the data shown and never grey out, and Undo on the record snackbar deletes the activity.
2. **Wave 2: the remaining critical and high tech debt** that touches the app, grouped one class per worktree:
   - `error-handling-and-observability/` — bootstrap failure, AsyncValue error states, sign-up errors;
   - `widget-state-and-view-logic/` — the previous user's data showing after sign-out, and the write layer;
   - `offline-and-write-reliability/` — persistence, timeouts, pending states on deletes;
   - `navigation-and-unreachable-ui/` — the four routes that dead-end on 404;
   - `auth-and-account-lifecycle/` — password reset, re-authentication;
   - `accessibility-and-localization/` — chart semantics, the record dialog at large text sizes.
   Classes that collide on the same files go in sequence, not in parallel.
3. **Release prerequisites from `ideas/`** marked "Needs Jack: no" in the release-blockers theme (account deletion is
   an App Store requirement), in the order `ideas/README.md` gives.
4. **The rest of the register**, medium then low, one class per PR.

Housekeeping that rides along with whatever PR touches it: delete each tech-debt file a PR fixes, and each idea file
a PR ships, with its README line and counts.

## Calls waiting on Jack (UNDECIDED)

Each needs a pitch with options and one recommendation before anything is built on it. Claude's recommendation is
in brackets; none of these is decided.

- **J1. Deploying the rules to production.** The Undo fix only reaches users once `firestore.rules` is deployed, and
  Claude may not contact the production project. Options: Jack runs
  `firebase deploy --only firestore:rules,firestore:indexes` once per change; or CI deploys rules on merge to
  `master` (the hosting service account would need the Firebase Rules Admin role). [CI deploy: it removes a manual
  step that will otherwise be forgotten, and the rules tests gate it.]
- **J2. `functions/`.** It is commented-out scaffolding whose build fails, on an end-of-life Node, and it carries
  most of the open Dependabot PRs. Options: delete it and close those PRs; or keep and repair it for future
  server-side work (subscriptions validation, reminders). [Delete; re-add when a server feature is chosen.]
- **J3. Which platforms ship.** iOS only, iOS and Android, or also the web build CI deploys today. Android builds
  fail and are debug-signed; the web build talks to production now. [iOS first; the end-to-end gate is iOS.]
- **J4. The business model.** See `ideas/` (monetisation theme) once wave 1's ideas PR lands.
- **J5. Licence.** No LICENSE exists and one manifest claims one. For a paid app the usual choice is proprietary,
  all rights reserved. [Proprietary.]
- **J6. Stale git state.** Two stashes over a year old, and merged or abandoned branches (`copilot/fix-9`,
  `add-time-graph`, `add-vice-function`, `manage-data`, `combine/archived-vices-plus-ios-fix`). Dropping stashes and
  deleting branches can't be undone. [Archive each stash as a commit on a local `archive/stashes` branch, then drop
  them; delete the merged branches; keep `copilot/fix-9` closed but undeleted.]

## For Jack to do (not decisions)

- Deploy the rules once J1 is decided, if the answer is "Jack runs it".

## How to test here

- **Never against production.** Emulators run with `--project demo-tracker`; see `CLAUDE.md` "Hard rules".
- `tools/e2e.sh` runs the integration tests on an iOS Simulator against the Auth and Firestore emulators
  (lands with `feat/emulator-e2e`). `tools/run-emulated.sh` launches the app against them for a manual look.
- Rules tests live in `tests/firestore-rules/` (lands with `fix/firestore-rules`).
- Only one agent at a time may use the simulator and the default emulator ports. Parallel agents that need an
  emulator use other ports (for example Firestore on 8180, hub 4410, logging 4510, UI off).
- Read the Firebase documentation before any change to rules, indexes, queries or emulator wiring, and cite it in
  the PR.

## Where the backlogs are

- `tech-debt/README.md` — what is wrong, by class and severity. Non-prescriptive; the fix is the PR's to design.
- `ideas/README.md` — what to build next, as pitches with a recommendation each, ordered as a roadmap to a paid
  release. Items marked "Needs Jack: yes" go to him as pitches before they are built.

## Thoughts

- The app is a small Flutter + Firestore codebase (about 3,000 lines in `lib/`) with no tests worth the name; most
  of the work before release is making it trustworthy, not adding screens.
- Writes are inline `FirebaseFirestore.instance` calls in widgets. A thin repository layer would make the write paths
  testable without the emulator; it is in the register as debt, not yet a decision.

## Set aside, with reasons

- **Rebasing or force-pushing the recovered feature branch** to tidy its history: it was already pushed, and
  force-pushing needs Jack. It merges `master` in instead.
