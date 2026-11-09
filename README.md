# Penchant

Habit journal & sleep insights: a journal for logging what you do, seeing the trends and learning about yourself. You
define a habit (a name and a unit), log activities against it, and read the trends: Today's Day Dial, a 24-hour face
of the day's entries, and the Trends sheet for one habit over a date range.

A Flutter app for iOS and macOS over Firebase Auth and Cloud Firestore, with one scheduled Cloud Function
(`functions/`). The code and stored data still call a habit a "vice" (`CLAUDE.md`).

## Run it

```bash
flutter pub get
tools/run-emulated.sh      # flutter run against local Firebase emulators (project demo-tracker)
```

Development runs against the emulators only; a plain `flutter run` talks to the production project. Every other
command (checks, tests, the Firestore rules tests) is in `CLAUDE.md`; seeding the emulators and versioning and
releases are the `seed-emulators` and `release` skills (`.claude/skills/`).

## Where things are

- `CLAUDE.md`: how the code works, the hard rules and the commands.
- `HANDOVER.md`: the current task queue and the calls waiting on the owner.
- `tech-debt/`: the debt register; `ideas/`: the product backlog. Both burn down by deletion (their READMEs).
- `CHANGELOG.md`: user-visible changes per release.
- `firestore.rules`, `firestore.indexes.json`: backend rules and indexes, which CI deploys to production on merge to
  `master`.

The code is proprietary; all rights reserved. See [LICENSE](LICENSE).
