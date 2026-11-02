# The PR workflow runs for a pull request against any base branch

**Severity:** low

`firebase-hosting-pull-request.yml` triggers on `pull_request` with no `branches` or `branches-ignore` filter. A full build and preview job therefore runs for a pull request opened against any base branch in the repository, not only ones targeting master.

## Evidence

- `.github/workflows/firebase-hosting-pull-request.yml:5` — `on: pull_request`
