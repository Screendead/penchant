# Tracker

A journal for tracking things you do and want to understand, such as a habit you are cutting down on. You define a
"vice" (a name and a unit), log activities against it, and read the trends: a per-day radar chart across your vices and
a line chart of one vice over a date range.

A Flutter app for iOS and macOS over Firebase Auth and Cloud Firestore. There is no server-side code. The product
name is not settled; "Tracker" is the working name.

## Run it

```bash
flutter pub get
tools/run-emulated.sh      # flutter run against local Firebase emulators (project demo-tracker)
```

`tools/run-emulated.sh` needs the Firebase CLI and Java. Always run emulators as
`firebase emulators:start --project demo-tracker`; a plain `flutter run` talks to the production project, which
development must never touch.

```bash
flutter analyze
flutter test
tools/e2e.sh               # integration tests on an iOS Simulator against the emulators
```

Commands for seeding data, the Firestore rules tests, versioning and releases are in `CLAUDE.md`.

## Where things are

- `CLAUDE.md`: how the code works, the hard rules, and every command.
- `HANDOVER.md`: the current task queue and the calls waiting on the owner.
- `tech-debt/`: the debt register, one short report per issue; a fixed issue's file is deleted.
- `ideas/`: the product backlog; a shipped or rejected idea's file is deleted.
- `CHANGELOG.md`: user-visible changes per release.
- `firestore.rules`, `firestore.indexes.json`: backend rules and indexes. CI deploys them on merge to `master` only once the `DEPLOY_FIRESTORE_RULES` repository variable is `true`; until then the deploy job is skipped and they are deployed by hand.

The app is proprietary; all rights reserved.
