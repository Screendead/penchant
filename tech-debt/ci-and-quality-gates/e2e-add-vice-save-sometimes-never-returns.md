# The end-to-end run's Add Vice save intermittently never completes

**Severity:** medium

`tools/e2e.sh` adds its vices through the Add Vice page and waits up to 30 seconds for the page to close after Save. In 2 of the suite's first 23 runs, during wave 1, that wait timed out. The cause is not confirmed.

The page awaits the Firestore `add` with no timeout of its own and closes only when the server acknowledges it, so a slow or lost acknowledgement leaves Save looking inert and the test has no message to report beyond the page still being open. A flake in the step every end-to-end test starts with fails the whole run, and the merge gate in `CLAUDE.md` depends on that run passing.

## Evidence

- `HANDOVER.md` queue item 1a — "`tools/e2e.sh`'s Add Vice save timed out in 2 of 23 early runs (cause unconfirmed)" (the wave 1 report; the failing runs' logs were not kept).
- `integration_test/support.dart:182` — `await tap(tester, find.widgetWithText(TextButton, 'Save'));\n    await pumpUntil(tester, find.text('Add Vice'), present: false);`
- `integration_test/support.dart:16` — `const Duration timeout = Duration(seconds: 30);`
- `lib/add_vice.dart:41` — `await FirebaseFirestore.instance.collection('vices').add({`
