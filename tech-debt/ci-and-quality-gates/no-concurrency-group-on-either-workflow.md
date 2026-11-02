# Overlapping runs are not cancelled, so the last deploy to finish wins

**Severity:** medium

Neither workflow declares a concurrency block. Two pushes to master in quick succession start two independent jobs with no ordering guarantee, and whichever hosting-deploy step finishes last determines what is live, not necessarily the job for the newer commit. The same applies to rapid updates on one PR branch, which queue overlapping jobs against the same preview channel.

## Evidence

- `.github/workflows/firebase-hosting-merge.yml:9` — `jobs:\n  build_and_deploy:\n    runs-on: ubuntu-latest`
- `.github/workflows/firebase-hosting-pull-request.yml:10` — `jobs:\n  build_and_preview:\n    if: ${{ github.event.pull_request.head.repo.full_name == github.repository }}\n    runs-on: ubuntu-latest`
