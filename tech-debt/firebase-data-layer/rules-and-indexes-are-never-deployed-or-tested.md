# Nothing in the repository deploys the rules or index files

**Severity:** medium

Both hosting workflows build Flutter web and call the hosting-deploy action with no other deploy targets, and no workflow runs `firebase deploy --only firestore`. The rules are unit-tested against the emulator on pull requests, but the emulator does not enforce composite indexes, so nothing checks the index file against the queries either.

Both files can therefore drift from the live project in either direction: an edit here reaches production only when someone deploys it by hand, and a console-side change never appears here.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:24` — `- uses: FirebaseExtended/action-hosting-deploy@v0`
- `.github/workflows/firebase-hosting-merge.yml:28` — `channelId: live, projectId: screendead-vice-tracker`
- **`grep -rn "deploy" .github/workflows/`** → only `action-hosting-deploy` steps
