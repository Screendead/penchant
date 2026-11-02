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

## Hard rules

- **Production Firestore is untouchable.** Never read or write the live data of `screendead-vice-tracker`, and never
  run a `firebase` or `gcloud` command that could contact that project (no `deploy`, no `firestore:*`, no
  `--project screendead-vice-tracker`). The documented data shape must stay compatible with existing documents.
  Deploying rules or indexes to production is Jack's to run.
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
- Merging to `master` deploys web hosting to production (CI); that is expected and allowed. It does not deploy rules.

## Commands

```bash
flutter pub get
flutter run                      # device picker; -d chrome for web
flutter analyze
dart run custom_lint             # riverpod_lint; analyze alone does not run it
flutter test
flutter test test/widget_test.dart --plain-name 'Material app smoke test'
flutter build web --release      # what CI builds and deploys
dart run flutter_launcher_icons  # after changing assets/icon.webp
```

Cloud Functions (`functions/`, Node 18, TypeScript):

```bash
npm --prefix functions run lint
npm --prefix functions run build
firebase deploy --only functions   # predeploy hook runs lint + build
```

Seed data: `node admin/populateFirestore.js`. It reads a service-account key from
`admin/privateKey.json`, which is gitignored; that file was deleted and its key rotated,
so the script has no credentials until a new one is supplied. It also predates the
`archived` field and writes vices without it, so `Vice.fromJson` throws on seeded data.

CI (`.github/workflows/`) builds web and deploys to Firebase Hosting on PR and on
merge to `master`. It runs neither tests nor `flutter analyze`.

## Architecture

A Flutter app over Firebase Auth + Firestore. Firebase project `screendead-vice-tracker`.

**Riverpod without codegen.** `riverpod_generator`, `riverpod_annotation`, and
`build_runner` are declared in `pubspec.yaml` but unused — there is no `@riverpod`
annotation and no `.g.dart` file anywhere. Every provider in `lib/providers/` is a
hand-written `StreamProvider` or `StreamProvider.family` wrapping a Firestore snapshot
stream. Match that style; running `build_runner` generates nothing.

**Reads go through providers, writes do not.** Widgets read via `ref.watch(...)` on a
provider, but write with inline `FirebaseFirestore.instance` calls (`add_vice.dart`,
`manage_data.dart`, `vice_activity_editor_page.dart`,
`widgets/record_new_activity_dialog.dart`). There is no repository layer.

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
enforces on read and write. `Unit` (`lib/data/unit.dart`) serializes as its enum name and
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

`functions/src/index.ts` is entirely commented-out scaffolding — there is no server-side
logic. Tests in `test/` run without Firebase: they override providers in a
`ProviderScope` or `ProviderContainer` (`test/fakes.dart` builds models and a mocked
`User`). Anything that calls `FirebaseFirestore.instance` is untestable that way.

The app always talks to production Firebase. `firebase.json` configures the full emulator
suite, but nothing in `lib/` calls `useEmulator`, so `firebase emulators:start` does not
affect the running app without wiring that up first.
