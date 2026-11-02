# Four merged local branches and three merged dependabot branches remain, plus one unmergeable stale branch

**Severity:** medium

`add-time-graph`, `add-vice-function`, `combine/archived-vices-plus-ios-fix`, and `manage-data` all satisfy a merged check against `origin/master` yet remain as local branches, the oldest untouched since August 2024.

Of eight remote dependabot branches, three are already ancestors of `origin/master` but were never deleted, and among the five unmerged, the `fast-xml-parser` 4.4.1 branch opened in July 2024 bumps to a version below the 4.5.0 bump already merged, so it can no longer land as-is.

## Evidence

- **`git branch --merged origin/master`** → `add-time-graph` / `add-vice-function` / `* chore/upgrade-flutter-and-all-deps-ios26` / `combine/archived-vices-plus-ios-fix` / `manage-data` / `master`
- **`git for-each-ref --sort=committerdate refs/heads/`** → `2024-08-13 add-vice-function a7e4617 Update dependencies to latest versions`
- **`git branch -r --merged origin/master`** → `origin/HEAD -> origin/master` / `origin/add-time-graph` / `origin/add-vice-function` / `origin/chore/upgrade-flutter-and-all-deps-ios26` / `origin/combine/archived-vices-plus-ios-fix` / `origin/dependabot/npm_and_yarn/functions/fast-xml-parser-4.5.0` / `origin/dependabot/npm_and_yarn/functions/micromatch-4.0.8` / `origin/dependabot/npm_and_yarn/functions/multi-9f37c16f8f` / `origin/manage-data` / `origin/master`
- **`git branch -r --no-merged origin/master`** → `origin/copilot/fix-9` / `origin/dependabot/npm_and_yarn/functions/brace-expansion-1.1.18` / `origin/dependabot/npm_and_yarn/functions/fast-xml-parser-4.4.1` / `origin/dependabot/npm_and_yarn/functions/multi-be700a2db9` / `origin/dependabot/npm_and_yarn/functions/multi-ff1d7b345e` / `origin/dependabot/npm_and_yarn/functions/websocket-driver-0.7.5`
- **`git log -1 --format='%ci %s' origin/dependabot/npm_and_yarn/functions/fast-xml-parser-4.4.1`** → `2024-07-29 22:52:55 +0000 Bump fast-xml-parser from 4.4.0 to 4.4.1 in /functions`
- **`git merge-base --is-ancestor origin/dependabot/npm_and_yarn/functions/fast-xml-parser-4.4.1 origin/master`** → not ancestor of master
