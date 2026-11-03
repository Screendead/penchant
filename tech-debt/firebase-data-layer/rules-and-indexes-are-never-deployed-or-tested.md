# The rules deploy job is off, and nothing checks the index file or console drift

**Severity:** medium

`deploy-firestore.yml` deploys the rules and index files on every push to `master`, but its deploy job is skipped
unless the repository variable `DEPLOY_FIRESTORE_RULES` is `true`, which needs the service account to hold the deploy
roles first. Until then an edit here reaches production only when someone deploys it by hand.

The rules suite runs against the emulator, which does not enforce composite indexes, so nothing checks the index file
against the queries. A console-side change to either never appears here, and once the job runs it overwrites the live
rules with this file's.

## Evidence

- `.github/workflows/deploy-firestore.yml:22` — `if: ${{ vars.DEPLOY_FIRESTORE_RULES == 'true' }}`
- `.github/workflows/rules-tests.yml:38` — `- run: npm test` (emulator only)
