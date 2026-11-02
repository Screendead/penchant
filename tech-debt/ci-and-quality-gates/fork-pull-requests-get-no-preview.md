# The preview job is skipped for pull requests whose head repository differs from the base

**Severity:** low

The PR workflow passes no channel id, so the hosting-deploy action auto-generates a per-PR preview channel rather than touching live, which only the merge workflow does. The job also carries an explicit repo-identity guard that skips it entirely for fork pull requests, on top of GitHub withholding repository secrets from fork-triggered runs; the repository is private, so this affects only contributors working from a fork.

## Evidence

- `.github/workflows/firebase-hosting-pull-request.yml:12` — `if: ${{ github.event.pull_request.head.repo.full_name == github.repository }}`
- `.github/workflows/firebase-hosting-pull-request.yml:26` — `- uses: FirebaseExtended/action-hosting-deploy@v0\n        with:\n          repoToken: ${{ secrets.GITHUB_TOKEN }}\n          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_SCREENDEAD_VICE_TRACKER }}\n          projectId: screendead-vice-tracker`
- **`gh api repos/Screendead/tracker --jq '.default_branch, .private'`** → `master\ntrue`
