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
| Standing rules (production safety, e2e gate, merge authority) | Merged 2026-11-02 (#24) | `CLAUDE.md` |
| CI checks: analyze and test on every PR; live deploy waits on them | Merged 2026-11-02 (#25) | `.github/workflows/checks.yml` |
| Emulator wiring and iOS end-to-end harness | Merged 2026-11-02 (#29) | `tools/e2e.sh`, `lib/firebase_init.dart` |
| Firestore rules rewrite (fixes Undo's permission-denied, closes cross-account writes), 55 rules tests, missing index | Merged 2026-11-02 (#27). **Not deployed to production**: J1 | `firestore.rules`, `tests/firestore-rules/` |
| Product ideas backlog: 26 pitches, 18 need Jack | Merged 2026-11-02 (#26) | `ideas/README.md` |
| Recovered features (day navigation, history, editor, usage graph, Undo) and fixes for Jack's two reported bugs | PR #28 ready: CI green, e2e 4/4 on the final head (2026-11-02). **Held until the rules are deployed**, because its three delete buttons fail against production's current rules | `feat/day-navigation-history-graph` |
| Decision pitch for every open call | Published 2026-11-02; Jack's picks save to the page | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs, source `docs/pitch/decisions.html` |
| Tech-debt register | 147 on master, 135 once #28 lands (from 162 on 2026-08-11) | `tech-debt/README.md` |

Baseline on master, measured 2026-11-02 on Flutter 3.44.7: `flutter analyze` clean, `flutter test` 1/1, rules tests
55/55, `tools/e2e.sh` 1/1 (3/4 earlier on #29; the failure was a radar-chart race in master's code that #28 removes).
On #28: `flutter test` 17/17, `tools/e2e.sh` 4/4. `dart run custom_lint` loads no rules (see the register). Re-measure;
don't trust this.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's standing calls. Work it top down; skip what is
blocked and say so. Items under one number can run in parallel in separate worktrees.

1. **Land #28** once Jack says the rules are deployed (J1). Merge `master` into it, re-run `tools/e2e.sh`, merge.
   Then delete `tech-debt/repo-docs-and-release-hygiene/claude-md-documents-uncommitted-state.md` if CLAUDE.md now
   matches master. Blocked on Jack.
2. **Apply Jack's picks** from the pitch page: read them with `ArtifactData` `list` on collection `picks` of
   https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs, record each call under "Calls" below as decided (with the date),
   and turn each into queue items. Build nothing on an unpicked call.
3. **Register what wave 1 found** (non-prescriptive entries, after #28 lands, since they describe its code): the usage
   graph's curve dips below zero around a single spike, its y-axis repeats "1" and its last two date labels overlap;
   pages opened from the drawer leave the drawer open behind them; `tools/e2e.sh`'s Add Vice save timed out in 2 of
   23 early runs (cause unconfirmed).
4. **Wave 2: the remaining critical and high tech debt** that touches the app, one class per worktree:
   - `error-handling-and-observability/`: bootstrap failure, AsyncValue error states, sign-up errors;
   - `widget-state-and-view-logic/`: the previous user's data showing after sign-out, and the write layer;
   - `offline-and-write-reliability/`: persistence, timeouts, pending states on deletes;
   - `navigation-and-unreachable-ui/`: the routes that dead-end on 404 (Manage Data's Edit is one);
   - `auth-and-account-lifecycle/`: password reset, re-authentication;
   - `accessibility-and-localization/`: chart semantics, the record dialog at large text sizes.
   Classes that touch the same files go in sequence, not in parallel. Only one agent at a time runs `tools/e2e.sh`.
5. **Release prerequisites from `ideas/`** marked "Needs Jack: no", in the order `ideas/README.md` gives (backend
   hardening, account deletion, versioning first).
6. **The rest of the register**, medium then low, one class per PR.

Housekeeping that rides along with whatever PR touches it: delete each tech-debt file a PR fixes, and each idea file
a PR ships, with its README line; run `tools/tech-debt-recount.py` (lands with #28) to fix the counts. It resolves
paths from its own location, so run the copy inside the worktree you are changing.

## Calls waiting on Jack (UNDECIDED)

Every open call is on the pitch page, with options, costs and one recommendation each:
https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs. Its ids, so picks map back here:

- **Unblocks the next merge:** `rules-deploy` (CI deploys rules on merge, or Jack runs it), `today-few-vices`,
  `record-timeout`, `undo-duration`, `clean-day`.
- **Foundations:** `functions` (delete `functions/` and its Dependabot PRs?), `platforms`, `licence`, `git-cleanup`
  (two year-old stashes, six stale branches), `e2e-ci`, `pr-previews`.
- **Rules details:** `quantity`, `name-length`, `vice-owner`.
- **Product keystones:** `positioning`, `framing`, `business`, `goals-fields` (optional new fields on `vices`, under
  the data-shape rule), `name`. The rest of the 18 "Needs Jack" ideas depend on these; pitch them after these land.

Not on the page, smaller: whether to upgrade the global Firebase CLI (15.8.0; 15.34 is current), which another
project's emulator files share.

## For Jack to do (not decisions)

- **Deploy the rules and indexes from master** (unblocks #28 and fixes Undo for users). Compare the live indexes with
  `firestore.indexes.json` first, and decline any offered index deletion:
  `firebase firestore:indexes --project screendead-vice-tracker`, then
  `firebase deploy --only firestore:rules,firestore:indexes --project screendead-vice-tracker`.
  The new rules check field types on every write, so an app build older than master may get permission-denied when it
  saves; rebuild any installed copy from master.
- Pick on the pitch page.

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
  (55 rules tests and 1 e2e test on master; 17 unit and widget tests and 4 e2e tests once #28 lands), but most of the
  app is still untested. Most of the work before release is making it trustworthy, not adding screens.
- Writes are inline `FirebaseFirestore.instance` calls in widgets. A thin repository layer would make the write paths
  testable without the emulator; it is in the register as debt, not yet a decision.

## Set aside, with reasons

- **Rebasing or force-pushing the recovered feature branch** to tidy its history: it was already pushed, and
  force-pushing needs Jack. It merges `master` in instead.
