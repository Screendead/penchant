# Nothing in the repository deploys, tests, or validates the rules or index files

**Severity:** medium

Both CI workflows build Flutter web and call the hosting-deploy action with no other deploy targets; neither runs `firebase deploy --only firestore`, a rules unit test, or a rules linter, and `test/` contains no rules tests.

Both files can therefore drift from the live project in either direction: an edit here never reaches production, and a console-side change never appears here. The validity of the rules file has never been demonstrated by anything in the repository.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:24` — `- uses: FirebaseExtended/action-hosting-deploy@v0`
- `.github/workflows/firebase-hosting-merge.yml:28` — `channelId: live, projectId: screendead-vice-tracker`
- **`ls test/`** → `test/widget_test.dart`
