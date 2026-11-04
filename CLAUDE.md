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
  `demo-` project has no cloud counterpart, so nothing can leak to production. `.firebaserc`'s `default` alias is
  `demo-tracker`, so a `firebase` command without `--project` lands there; the deploy workflow names production with
  `--project`. A `firebase use` in a directory overrides `.firebaserc` there (the CLI keeps it in
  `~/.config/configstore/firebase-tools.json`), so never run `firebase use screendead-vice-tracker`.
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
dart analyze --fatal-infos --fatal-warnings  # what CI runs; flutter analyze omits riverpod_lint
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

CI (`.github/workflows/`): `checks.yml` runs `dart analyze --fatal-infos --fatal-warnings`
and `flutter test` on every PR to `master`. `rules-tests.yml` runs the Firestore rules suite on
every PR. On a push to `master`, `deploy-firestore.yml` re-runs both and, only if they pass, deploys
`firestore.rules` and `firestore.indexes.json` to production with the firebase-tools pinned in
`tests/firestore-rules/package-lock.json`. Its deploy job is skipped unless the repository variable
`DEPLOY_FIRESTORE_RULES` is `true`, and deploys queue in one concurrency group so the newest commit lands
last. Nothing builds or deploys the app. Flutter is pinned in
`.github/actions/setup-flutter/action.yml`; bump it there when the local `flutter --version`
changes. riverpod_lint runs as an analyzer plugin (top-level `plugins:` in `analysis_options.yaml`, not a
`pubspec.yaml` dependency), pinned to 3.1.4: 3.1.6 to 3.1.8 resolve an `analysis_server_plugin` whose protocol the
Dart 3.12 server does not speak, so the plugin never starts and `dart analyze` hangs. Move it forward when the
Flutter pin ships Dart 3.13 (3.1.9 needs it). Its warnings fail `dart analyze` and show in the IDE; on this pin
`flutter analyze` prints none of them, so CI analyzes with `dart analyze`.

## Architecture

A Flutter app over Firebase Auth + Firestore. Firebase project `screendead-vice-tracker`.
It targets iOS and macOS only; `firebase_options.dart` throws on any other platform.

**Riverpod without codegen.** No code generation: every provider in `lib/providers/` is
hand-written, and nothing in `pubspec.yaml` generates them. `userProvider` is a plain `StreamProvider` over `authStateChanges()`, and
`userProfileProvider` one over `userChanges()`. Each
Firestore query is a `...ForUserProvider`, a `StreamProvider.autoDispose.family` over a
snapshot stream (the Manage Data count is a `FutureProvider.autoDispose.family` over a
`count()` aggregation, which falls back to counting the cached documents while
`offlineProvider` says offline or the server cannot answer, says which, and retries
after a server failure), read through a `Provider.autoDispose` (or `Provider.autoDispose.family`)
of `AsyncValue` that supplies the signed-in uid (Provider chain, below). Don't add a
query provider that watches `userProvider` itself: that shape leaked the previous user's
data. `trackerWritesProvider` is a plain `Provider` that hands out the write layer
(below), and `packageInfoProvider` is a `FutureProvider` over
`PackageInfo.fromPlatform()`, for the version under Settings > About. `todayProvider` is a
`NotifierProvider` holding the start of the current local day. Match that style.

**Reads and writes both go through providers.** Widgets read via `ref.watch(...)` on a
provider of `AsyncValue` and write via `ref.read(trackerWritesProvider)`, which hands out one
`TrackerWrites` (`lib/writes/tracker_writes.dart`), which makes every write the
screens make to a single document. It has one method
per write (`addVice`, `setViceArchived`, `newActivityID`, `recordActivity`,
`updateActivity`, `deleteActivity`) and returns the SDK's future unchanged; timeouts,
error messages and Undo stay in the widgets. Each widget hands the future to `settleWrite`
(`lib/writes/settle_write.dart`), which waits ten seconds and then calls the write queued.
It keeps listening, and a refusal after that goes to `onRejectedLater`: widgets pass
`ref.read(rejectedWritesProvider.notifier).reporter('<what, named at write time>')`. That
`NotifierProvider` (`lib/writes/rejected_writes.dart`) holds the refused changes of the
signed-in user, cleared when the uid changes, and `MaterialApp.builder`
(`lib/widgets/rejected_writes_banner.dart`) shows them above every screen until dismissed.
A write queued by an earlier launch has no future to listen to, so its refusal is not seen. The record dialog takes one id from
`newActivityID()` per dialog, so a second press after a failed save writes the same
document. Every Firebase Auth call goes through `ref.read(accountProvider)`, one `Account`
(`lib/account/account.dart`): sign-in, register (which also sends the verification email),
password reset, re-authentication, profile and email changes, sign-out, and the
account-wide Firestore work: `fetchData` pages through the user's vices and activities for
export, from the server so that offline it fails instead of returning a partial cache (`lib/account/export.dart` builds the CSV and JSON; `exportShareProvider` hands them
to the share sheet), and `deleteAccount` re-authenticates, deletes every owned document in
batches of 500, then the Auth user; a failure after the first batch is a
`DeletionIncompleteException`, and any other failure removed nothing. Sign-out and deletion then `terminate()` Firestore and
`clearPersistence()`; the Dart instance keeps the settings `firebase_init.dart` gave it (the
cache, or the emulator host), and the plugin builds a fresh native instance from them on the
next call. Sign-out first waits up to 5 s for pending writes and throws
`UnsyncedEntriesException` rather than discard them silently. Auth error text shown to the
user comes from `authErrorMessage` (`lib/account/auth_errors.dart`), never Firebase's own
message; the account and deletion copy lives in `lib/account/account_copy.dart`.

**Provider chain.** Each Firestore query is a `...ForUserProvider` family keyed on the
uid (and its other parameters), wrapped by a plain provider of `AsyncValue` that selects
the uid from `userProvider` through `watchForSignedInUser`
(`lib/providers/signed_in_user.dart`): `viceListProvider` and the activity day, history,
graph, single-activity and count providers. `unarchivedViceListProvider` filters
`viceListProvider`'s list on the device rather than querying on `archived`: a filter on a
field matches only documents that hold it, and vices written before 2024-08-14 lack it. The wrapper is
loading with no value while nobody is signed in, and each user's query is a separate
provider, so a value never belongs to a previous user: riverpod carries a provider's last
value into the loading state of a rebuild, which is how a single provider rebuilt on a user
change leaked the previous account's data. Widgets watch the wrapper; tests override it
with an `AsyncValue`, or override the family to test the wrapper. The query families are
`autoDispose`, so leaving a day, range or page closes its listener, and so are the wrappers:
a wrapper nothing watches would keep its family's listener open, and once sign-out has
terminated Firestore that listener hears nothing, so the same user signing back in would
see a frozen list. No activity provider
depends on the vice list: the day query filters on `ownerID` and `createdAt` alone (an `in`
filter on vice IDs takes at most 30) and the chart drops activities of vices it does not
draw. A `null` value means loading; an empty list means no data. Never gate UI on
`ref.read(provider.future)`: in riverpod 3 a read with no other listener pauses the
provider's stream, so the future never resolves. Render loading and error from the watched
`AsyncValue` instead. A `User` is a snapshot that profile updates and `reload()` never
change: only `userChanges()` re-emits after them, and it also fires on every token refresh.
So Account Settings alone watches `userProfileProvider`, and calls `Account.reloadUser()` on
opening and on app resume to pick up a verification made elsewhere; the chain stays on
`userProvider`.

**Query bounds.** The day and graph queries are bounded by their date window, the history
page asks for 50 at a time (`ViceActivityHistoryPage.pageSize`, plus one to learn whether
older entries exist), the editor listens to its one document, and Manage Data counts each
vice's activities with a server-side `count()` aggregation, which is not live, ignores
writes still queued on the device, and fails offline. The vice lists have no limit, and
nothing caps how many vices a user creates; whether to add a cap is undecided (register,
`vice-lists-are-unbounded`).

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
from the today chart but keeps its history, which stays reachable: Manage Data still opens
it and the Graph lists archived vices last, marked "(archived)", never as the default.

**Days.** An entry counts on the local calendar day, in the viewing device's current time zone, of the instant
stored in its `createdAt`. Day windows and graph buckets are local midnights built with `lib/data/day.dart`
(never `Duration(days:)`, which drifts an hour across a DST change). The zone an entry was logged in is not
stored, so an entry near midnight can move a day when viewed in another zone; storing it would be a new activity
field (the open `r2-data-model` call). `createdAt` is the device's clock at the moment of logging (or the time the
user picked), not a server timestamp: a pending `FieldValue.serverTimestamp()` matches no `createdAt` range query
until the server acknowledges it, so an entry logged offline would vanish from Today, and the server would stamp it
with the time it synced. Whether to trade that for server time is open (register,
`activity-timestamps-come-from-the-device-clock`).

Any new composite query shape needs a matching entry in `firestore.indexes.json`;
Firestore throws `failed-precondition` at runtime until the index is deployed.

**Navigation.** `main.dart` gates on `userProvider`: a user → `Homepage`, an error →
`AuthStateFailure`, no event yet → `AuthStateLoading` (so a restored session never shows
sign-in first), and a null user → `Authenticate`. `generateRoute` maps a route's path segments to a page through `routePage`, a
pattern `switch` (`/vices/:viceID/edit`, `/vices/:viceID/activities[/:activityID]`, ...);
anything else is `NotFound`. Only the forms (add or edit a vice, edit an activity) open as
fullscreen dialogs. When the signed-in user changes, `MyApp` pops every pushed route, since
swapping `home` alone would leave the old session's pages on the stack.

**Two home tabs.** `ViceTracker` shows one day at a time as an `fl_chart` radar chart
(`vice_chart.dart`), one axis per unarchived vice. `UsageGraphView` shows one vice over a
date range as a line chart, bucketing activities by day or by week (counted back from today, so the newest week is
whole and the oldest bucket holds what is left of the range) and overlaying a moving average; that arithmetic and both charts' axis scales and label spacing are pure functions in
`lib/data/usage_series.dart` and `lib/data/chart_scale.dart`. Below three vices Today draws bars instead (fl_chart's
radar needs three axes). The radar carries
a second, invisible data set that pins its centre to 0 and its outer ring to a round number, since fl_chart
centres on the smallest entry of all data sets. Each chart sits in one `Semantics` node whose label is a
text summary of the data (`ViceChart.summary`, `UsageGraphView.summary`), and fl_chart paints its titles
outside the widget tree, so tests read them from the chart's data. Homepage builds only the visible tab;
each tab keeps its selections in Homepage's `PageStorage` bucket. Both read the current day from
`todayProvider`, which moves on at local midnight and on app resume; the Today tab follows it unless the
user picked another day. Activity dates go through `ActivityDateField` (`lib/widgets/`), the one
format, lock toggle, live clock and picker for the record dialog and the editor.

There is no server-side logic. Tests in `test/` run without Firebase: they override providers in a
`ProviderScope` or `ProviderContainer` (`test/fakes.dart` builds models and a mocked
`User`; `test/fake_writes.dart` is a `TrackerWrites` that records each write, for
`trackerWritesProvider.overrideWithValue`; `test/fake_account.dart` does the same for
`accountProvider` and `exportShareProvider`). Anything that calls `FirebaseFirestore.instance`
or `FirebaseAuth.instance` directly is untestable that way;
`integration_test/` drives the real app on an iOS Simulator against the emulators instead. Both
that and the rules suite are described under Commands.

**Offline.** Production Firestore runs with disk persistence and an explicit 100 MB cache
(`_configureFirestoreCache` in `lib/firebase_init.dart`); the emulator path keeps persistence off. Every
write awaits through `settleWrite` (`lib/writes/settle_write.dart`): an acknowledgement within ten seconds
is success, a timeout means the write is queued and the UI says it will sync, and only a
`FirebaseException` is a failure. `ViceActivity.pending` carries `hasPendingWrites`; the day and history
providers listen with `includeMetadataChanges: true` so the server's acknowledgement clears it.
`offlineProvider` is true once a vices listener has answered from the cache for three seconds, which
drives the offline banner and the offline wording of an empty day.

**Emulator wiring.** `lib/firebase_init.dart` does all Firebase setup. Without the
`USE_FIREBASE_EMULATORS` dart-define it is the original `initializeApp` call against
production. With it, the default app is initialized with `demo-tracker` options, Firestore
persistence is off, Auth and Firestore point at `localhost`, and startup throws if the
default app resolves to a non-`demo-` project. App Check is activated right after
`initializeApp` in both modes and enforced nowhere: App Attest with the DeviceCheck
fallback in production, the debug provider (no committed token) under the emulators, which
ignore App Check. App Attest yields no accepted token until the Runner target carries the
App Attest entitlement, which the current signing team cannot sign (HANDOVER.md). On iOS, firebase_core configures the native
default app from the bundled `GoogleService-Info.plist` before Dart runs, so the Runner
target's "Strip Firebase plist for emulators" build phase
(`tools/ios-strip-firebase-plist.sh`) moves it out of the bundle for flagged builds. macOS
bundles its own plist with no such phase, so a flagged macOS build should fail at startup.
