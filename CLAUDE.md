# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
means no data.

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
logic. The test suite is a single smoke test.

The app always talks to production Firebase. `firebase.json` configures the full emulator
suite, but nothing in `lib/` calls `useEmulator`, so `firebase emulators:start` does not
affect the running app without wiring that up first.
