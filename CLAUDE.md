# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State and the current task

This file holds how the code works. `HANDOVER.md` holds the current task: the queue, where each item stands, the
calls waiting on Jack, and the options set aside with their reasons. Read it at the start of every session; "do the
next thing" means the top unblocked item in its queue. Update it in the same commit that closes an item or records a
call. If this file and `HANDOVER.md` disagree about state, `HANDOVER.md` wins. Record a recommendation as a
recommendation until Jack decides it.

`tech-debt/` is the debt register and `ideas/` is the product backlog. Both burn down by deletion: when an issue is
fixed or an idea ships or is rejected, delete its file (and its README line) in the same PR.
`tools/tech-debt-recount.py` recomputes the register's counts, drops lines whose file is gone, keeps both sides of
a merge conflict in `tech-debt/README.md`, and fails if a report file has no line.

## Hard rules

- **Production Firestore is untouchable.** Never read or write the live data of `screendead-vice-tracker`, and never
  run a `firebase` or `gcloud` command that could contact that project (no `deploy`, no `firestore:*`, no
  `--project screendead-vice-tracker`). The documented data shape must stay compatible with existing documents:
  new optional fields are fine; a new mandatory field ships only with a migrator that adds it to existing records on
  first launch (Jack, 2026-11-03). Rules and indexes reach production only through CI on merge to `master` (Jack,
  2026-11-03), so merging a rules PR deploys it; until Jack enables that job (the `DEPLOY_FIRESTORE_RULES`
  repository variable), he deploys them by hand.
- **Emulators use a `demo-` project.** Run every emulator as `firebase emulators:start --project demo-tracker`. A
  `demo-` project has no cloud counterpart, so nothing can leak to production.
- **Firebase docs first.** Before changing `firestore.rules`, `firestore.indexes.json`, a query, or anything about the
  emulators, read the current Firebase documentation for it (firebase.google.com/docs) and cite the page in the PR.
- **End-to-end before merge.** A change that touches app behaviour merges only after it has run end to end on an iOS
  Simulator against the Firebase emulators (`tools/e2e.sh`, see HANDOVER.md), and the PR says what was exercised.

## Git, pull requests and merging

- Branch and PR for every change; never commit to `master`. Open PRs without asking. Worktrees go under
  `~/development/tracker-worktrees/`.
- **Claude may merge PRs without asking Jack** (Jack, 2026-11-02), once CI passes, the end-to-end run above passed
  where it applies, and Claude is satisfied with the diff. A PR that rests on a call Jack hasn't made still waits for
  him. Force-pushing `master` always needs Jack.
- Workflow subagents cannot merge: the auto-mode permission classifier denies `gh pr merge` inside them ("Merge
  Without Review"). They bring a PR to green and CLEAN; the main session merges.

## Commands

```bash
flutter pub get
flutter run                      # device picker; -d macos for the desktop build
flutter analyze
dart run custom_lint             # loads no rules: riverpod_lint 3.1 left custom_lint (see tech-debt)
flutter test
flutter test test/widget_test.dart --plain-name 'Material app smoke test'
flutter build macos --debug      # the macOS target still builds (CI builds no app)
dart run flutter_launcher_icons  # after changing assets/icon.webp
```

End to end against the Firebase emulators (Auth + Firestore, project `demo-tracker`):

```bash
tools/e2e.sh                      # integration_test/ on the first available "iPhone 18 Pro" simulator; exits with the test status
tools/e2e.sh integration_test/smoke_test.dart
E2E_DEVICE=<udid> tools/e2e.sh    # another simulator, or where no "iPhone 18 Pro" exists; never let flutter pick (a physical iPhone may be attached)
tools/run-emulated.sh             # flutter run against fresh emulators; Emulator UI on http://localhost:4000
tools/e2e-screenshots.sh <dir> [file]  # e2e.sh plus a PNG in <dir> for each screenshot(tester, name) call
```

Both boot the simulator by UDID (looked up by name unless `E2E_DEVICE` is set), refuse to start if an emulator port
(8080, 9099, 9150, 4000, 4400, 4500) is taken, and start the emulators under `demo-tracker` from
`tools/emulator-env.sh`. `flutter test integration_test` without `--dart-define=USE_FIREBASE_EMULATORS=true` fails in
`setUpAll` rather than run against production.

Versions and releases. `version:` in `pubspec.yaml` is the user-facing semantic version (0.x until the first App
Store release); its `+N` is a placeholder. The build number of any shipped build is the commit count on `master`, so it
rises with every merge and App Store Connect never sees a repeat. Build with the helper's flags, never by hand:

```bash
tools/build-version.sh            # --build-name=0.1.0 --build-number=212 (needs full history, not a shallow clone)
flags=$(tools/build-version.sh) && flutter build ipa $flags
```

To release: add the PR lines under `## [Unreleased]` in `CHANGELOG.md` as you go; in a release PR bump `version:`,
rename that section to `## [X.Y.Z] - <date>`, and merge. Then run the Release workflow
(`gh workflow run release.yml --repo Screendead/tracker`) on `master`: it re-runs the checks, tags `vX.Y.Z` and
publishes that changelog section as the release notes (`tools/changelog-section.sh X.Y.Z` prints it). It refuses a
version that already has a release. The app shows `version (build)` under Settings > About.

Seed data, into emulators only (Node 22, `npm --prefix admin ci` once). `emulators:exec` sets the emulator hosts
itself but discards the data when the script exits, so it only checks that the script runs:

```bash
firebase emulators:exec --project demo-tracker --only auth,firestore "node admin/populateFirestore.js"
```

To keep the data, start `tools/run-emulated.sh` (or `firebase emulators:start --project demo-tracker`), then in
another terminal point the script at its ports and log in as the seed user:

```bash
FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 node admin/populateFirestore.js
```

`admin/populateFirestore.js` refuses to start unless `FIRESTORE_EMULATOR_HOST` and
`FIREBASE_AUTH_EMULATOR_HOST` are set and the project id (`SEED_PROJECT_ID`, default `demo-tracker`)
starts with `demo-`; it needs no credentials. It creates the Auth user `seed@example.com` (password
`seed-password`) and replaces that user's vices (one archived) and 30 days of activities with documents in the
current data shape.

Firestore rules tests (`tests/firestore-rules/`, Node 22, `node --test` under the
Firestore emulator on `demo-tracker`):

```bash
npm --prefix tests/firestore-rules ci
npm --prefix tests/firestore-rules test   # needs Java 21; uses the firebase.json ports
```

To run beside another emulator, point `firebase emulators:exec` at a config outside the
repo with other ports: `npm --prefix tests/firestore-rules test -- --config <path>`.

CI (`.github/workflows/`): `checks.yml` runs `flutter analyze --fatal-infos --fatal-warnings`
and `flutter test` on every PR to `master`. `rules-tests.yml` runs the Firestore rules suite on
every PR. On a push to `master`, `deploy-firestore.yml` re-runs both and, only if they pass, deploys
`firestore.rules` and `firestore.indexes.json` to production with the firebase-tools pinned in
`tests/firestore-rules/package-lock.json`. Its deploy job is skipped unless the repository variable
`DEPLOY_FIRESTORE_RULES` is `true`, and deploys queue in one concurrency group so the newest commit lands
last. Nothing builds or deploys the app. Flutter is pinned in
`.github/actions/setup-flutter/action.yml`; bump it there when the local `flutter --version`
changes. No riverpod_lint rule runs anywhere, locally or in
CI, until `tech-debt/dependency-and-tooling-drift/custom-lint-plugin-cannot-load-riverpod-lint.md`
is fixed.

## Architecture

A Flutter app over Firebase Auth + Firestore. Firebase project `screendead-vice-tracker`.
It targets iOS and macOS only; `firebase_options.dart` throws on any other platform.

**Riverpod without codegen.** `riverpod_generator`, `riverpod_annotation`, and
`build_runner` are declared in `pubspec.yaml` but unused — there is no `@riverpod`
annotation and no `.g.dart` file anywhere. Every provider in `lib/providers/` is
hand-written. Most are a `StreamProvider` or `StreamProvider.family` wrapping a Firestore
snapshot stream (`userProvider` wraps `authStateChanges()`). Two are plain `Provider`s:
`viceActivityListByViceIDProvider` groups `viceActivityListProvider`'s resolved list by
vice and returns `null` until that list has a value, and `trackerWritesProvider` hands
out the write layer (below). `packageInfoProvider` is a `FutureProvider` over
`PackageInfo.fromPlatform()`, for the version under Settings > About. Match that style; running `build_runner` generates nothing.

**Reads and writes both go through providers.** Widgets read via `ref.watch(...)` on a
stream provider and write via `ref.read(trackerWritesProvider)`, which hands out one
`TrackerWrites` (`lib/writes/tracker_writes.dart`), which makes every per-document
write. It has one method
per write (`addVice`, `setViceArchived`, `newActivityID`, `recordActivity`,
`updateActivity`, `deleteActivity`) and returns the SDK's future unchanged; timeouts,
error messages and Undo stay in the widgets. The record dialog takes one id from
`newActivityID()` per dialog, so a second press after a failed save writes the same
document. Every Firebase Auth call goes through `ref.read(accountProvider)`, one `Account`
(`lib/account/account.dart`): sign-in, register (which also sends the verification email),
password reset, re-authentication, profile and email changes, sign-out, and the
account-wide Firestore work: `fetchData` pages through the user's vices and activities for
export (`lib/account/export.dart` builds the CSV and JSON; `exportShareProvider` hands them
to the share sheet), and `deleteAccount` re-authenticates, deletes every owned document in
batches of 500, then the Auth user. Sign-out and deletion then `terminate()` Firestore and
`clearPersistence()`; the plugin builds a fresh native instance with the same settings on
the next call. Sign-out first waits up to 5 s for pending writes and throws
`UnsyncedEntriesException` rather than discard them silently. Auth error text shown to the
user comes from `authErrorMessage` (`lib/account/auth_errors.dart`), never Firebase's own
message; the account and deletion copy lives in `lib/account/account_copy.dart`.

**Provider chain.** `userProvider` (auth state) → `viceListProvider` /
`unarchivedViceListProvider` → the day and list activity providers, which need the vice
list to build their `whereIn` clause; the history, graph, and window providers depend on
`userProvider` alone. Each returns `Stream.empty()` when the user is null, so `.value`
stays `null` and widgets render a spinner. A `null` list means loading; an empty list
means no data. The day and list activity providers emit an empty list for an empty vice
list, since Firestore rejects an empty `whereIn`, and forward a vice-list error rather
than staying in loading. Never gate UI on `ref.read(provider.future)`: in riverpod 3 a
read with no other listener pauses the provider's stream, so the future never resolves.
Render loading and error from the watched `AsyncValue` instead.

**Data model.** Two flat top-level collections joined by `viceID`: `vices`
(`name`, `unit`, `ownerID`, `createdAt`, `archived`) and `activities` (`viceID`,
`quantity`, `ownerID`, `createdAt`). Both carry `ownerID`, which `firestore.rules`
checks against the stored document on read, update and delete and against the incoming
one on create. The rules also fix each collection's field set and types on create, allow
updates only to `name`/`unit`/`archived` (vices) and `quantity`/`createdAt`
(activities), and validate only the changed fields on update so legacy documents
(vices without `archived`, names over 60, zero quantities, activities whose vice is gone)
stay readable and editable. A vice name is 1 to 60 UTF-16 code units (rules `size()`,
Dart `String.length`); a quantity is an int of at least 1; a new activity's `viceID`
must name a vice the writer owns, checked with one `get()` (a billed read, even when
denied). `lib/data/limits.dart` holds the form validators that mirror these. The parsers never throw:
`lib/data/json_fields.dart` reads each field with a default for a missing or mistyped value
(empty string, `false`, 0, the nearest int for a double, `Unit.item`, and for `createdAt` the epoch, or now
while the document has pending writes and its server timestamp is unresolved). A new field needs a rules change and a test. `Unit` (`lib/data/unit.dart`) serializes as its enum name and
supplies singular/plural labels for the UI. Archiving a vice hides it from recording and
from the today chart but keeps its history.

Any new composite query shape needs a matching entry in `firestore.indexes.json`;
Firestore throws `failed-precondition` at runtime until the index is deployed.

**Navigation.** `main.dart` gates on `userProvider`: null user → `Authenticate`, otherwise
`Homepage`. `onGenerateRoute` parses the route as a URI, so `/vices/:viceID/activities` and
`/vices/:viceID/activities/:activityID` are matched by path segments; the rest are a
`switch` on the literal name.

**Two home tabs.** `ViceTracker` shows one day at a time as an `fl_chart` radar chart
(`vice_chart.dart`), one axis per unarchived vice. `UsageGraphView` shows one vice over a
date range as a line chart, bucketing activities by day or week and overlaying a moving
average.

There is no server-side logic. Tests in `test/` run without Firebase: they override providers in a
`ProviderScope` or `ProviderContainer` (`test/fakes.dart` builds models and a mocked
`User`; `test/fake_writes.dart` is a `TrackerWrites` that records each write, for
`trackerWritesProvider.overrideWithValue`; `test/fake_account.dart` does the same for
`accountProvider` and `exportShareProvider`). Anything that calls `FirebaseFirestore.instance`
or `FirebaseAuth.instance` directly is untestable that way;
`integration_test/` drives the real app on an iOS Simulator against the emulators instead. Both
that and the rules suite are described under Commands.

**Emulator wiring.** `lib/firebase_init.dart` does all Firebase setup. Without the
`USE_FIREBASE_EMULATORS` dart-define it is the original `initializeApp` call against
production. With it, the default app is initialized with `demo-tracker` options, Firestore
persistence is off, Auth and Firestore point at `localhost`, and startup throws if the
default app resolves to a non-`demo-` project. On iOS, firebase_core configures the native
default app from the bundled `GoogleService-Info.plist` before Dart runs, so the Runner
target's "Strip Firebase plist for emulators" build phase
(`tools/ios-strip-firebase-plist.sh`) moves it out of the bundle for flagged builds. macOS
bundles its own plist with no such phase, so a flagged macOS build should fail at startup.
