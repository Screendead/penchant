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
| Standing rules, CI checks, emulator and iOS e2e harness | Merged 2026-11-02 (#24, #25, #29) | `CLAUDE.md`, `.github/workflows/`, `tools/e2e.sh` |
| Firestore rules rewrite (#27) | Deployed to production by Jack 2026-11-03 | `firestore.rules` |
| Recovered features and the fixes for Jack's two reported bugs (#28) | Merged and live 2026-11-03 | `lib/` |
| Jack's round-1 calls C1–C19 | Picked 2026-11-03; built in wave 3 | below |
| Wave 3: Today and recording C2–C5 (#36), rules details C12–C14 (#33), platform and repo cleanup C1 C6–C11 (#34), ideas rework C15–C19 (#35) | Merged 2026-11-03. The rules from #33 are **not yet in production**: they deploy through CI once Jack enables it (below) | `lib/`, `firestore.rules`, `.github/workflows/deploy-firestore.yml`, `ideas/` |
| Round-2 calls (16) | Open on the pitch page since 2026-11-03 | https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs |
| Tech-debt register | 110 issues, 0 critical (from 162 on 2026-08-11) | `tech-debt/README.md` |
| Product backlog | 33 ideas for the journal positioning, roadmap in its README | `ideas/README.md` |

Baseline on master, measured 2026-11-03 on Flutter 3.44.7: `flutter analyze` clean, `flutter test` 32/32, rules
tests 72/72, `tools/e2e.sh` 6/6. `flutter build macos` fails (deployment target; queue 1). `dart run custom_lint`
loads no rules (see the register). Re-measure; don't trust this.

## The queue (DECIDED work, in order)

Each item is decided: its goal is clear or follows from Jack's calls below. Work it top down; skip what is blocked
and say so. Items under one number can run in parallel in separate worktrees; only one agent at a time runs
`tools/e2e.sh` or uses the default emulator ports. Subagents write PR bodies to uniquely named scratchpad files: the
scratchpad is shared, and a generic `pr-body.md` once put one PR's description on another.

1. **macOS as a fully supported target** (C6's note): it builds (the register's frozen-deployment-target entry), runs
   against the emulators, has its own e2e run, and CI builds it. Registering a macOS app in the Firebase console is a
   production action: if one is needed, it goes on Jack's list.
2. **What the reworked roadmap marks as needing no call** (`ideas/README.md`, step 2), in its order: parsers that
   default every missing field (before any new field is written), backend hardening, account deletion, versioning,
   offline logging, export, one-tap logging. Parallel where the files don't overlap.
3. **Wave 2: the remaining high tech debt** that touches the app, one class per worktree:
   - `error-handling-and-observability/`: bootstrap failure, AsyncValue error states, sign-up errors;
   - `widget-state-and-view-logic/`: the previous user's data showing after sign-out, and the write layer;
   - `offline-and-write-reliability/`: persistence and pending states on deletes;
   - `navigation-and-unreachable-ui/`: the routes that dead-end on 404 (Manage Data's Edit is one);
   - `auth-and-account-lifecycle/`: password reset, re-authentication;
   - `accessibility-and-localization/`: chart semantics, the record dialog at large text sizes. Register first (not
     yet in it): the radar plots 0 away from the centre, with a "0.0" tick on the middle ring.
   Classes that touch the same files go in sequence, not in parallel.
4. **Round-2 calls, once picked**: record each below with the date, then queue its work. Build nothing on an unpicked
   call. Read the picks with `ArtifactData` `list` on collection `picks` of the pitch page (ids start `r2-`).
5. **The rest of the register**, medium then low, one class per PR.

Housekeeping that rides along with whatever PR touches it: delete each tech-debt file a PR fixes, and each idea file
a PR ships, with its README line; run `tools/tech-debt-recount.py` to fix the counts. It resolves paths from its own
location, so run the copy inside the worktree you are changing.

## Jack's calls, round 1 (2026-11-03)

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
- **C16. Framing** (`framing`): **neutral, rated 17+**, with a disclaimer. Apple retired 17+ in July 2025; round 2
  (`r2-age`) asks Jack to confirm 18+.
- **C17. Business model** (`business`): **free 1.0, then a one-time Pro unlock in 1.1.**
- **C18. New fields on vices** (`goals-fields`): **yes.** Optional fields are fine. Mandatory fields are allowed too,
  but only with a migrator that runs on first launch and adds them to existing records.
- **C19. Name** (`name`): **a distinct brand plus a descriptive subtitle.** The brand itself is open on the pitch page (`r2-brand`;
  candidates in `ideas/release-blockers/brand-name.md`).

## Calls waiting on Jack (UNDECIDED)

Round 2 is on the pitch page, https://claude.ai/artifact/FP7t44ss9JtF9BXfhMcFNs, each with options and one
recommendation. Ids: `r2-web-site` (when the live web site goes down), `r2-brand`, `r2-trademark`, `r2-age` (18+ in
place of the retired 17+), `r2-data-model` (fields on activities, decimals, new collections), `r2-days`, `r2-mac`,
`r2-pro` (the free/Pro line and price), `r2-billing`, `r2-signin`, `r2-crash`, `r2-testflight` (a separate beta
Firebase project), `r2-privacy`, `r2-icon`, `r2-applock`, `r2-cli` (upgrade the global Firebase CLI).

Pitched later, with mock-ups, when their work starts: the starter trigger tree's top two levels
(`ideas/insights/trigger-tagging.md`), the onboarding presets and their wording, and the Today layout.

## For Jack to do (not decisions)

- **Let CI deploy rules (C1):** grant the service account behind `FIREBASE_SERVICE_ACCOUNT_SCREENDEAD_VICE_TRACKER`
  Firebase Rules Admin, Cloud Datastore Index Admin and Service Usage Consumer, and keep Firebase Hosting Admin (or
  add Firebase Viewer) for `firebase.projects.get`; then
  `gh variable set DEPLOY_FIRESTORE_RULES --body true --repo Screendead/tracker`. Until then the deploy job is skipped
  and #33's rules stay undeployed. The next merge after that deploys them; rebuild installed copies from master first.
- **Send Claude in chat:** the privacy policy's legal entity, contact address and data-controller details; the
  support email; the TestFlight testers. They stay out of the repo.
- **PR #22** (a Dependabot bump in `admin/`) is open; it is safe to leave until the seed script is reworked.

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
- **Android release, the web app, Cloud Functions, PR previews** (C6, C7, C11): removed 2026-11-03; re-add only on a
  new call.
- **Harm-reduction framing, and the moderation, alcohol-only and quit-counter positionings** (C15, C16): the app is a
  neutral journal. Goals and limits survive as an optional, later feature.
