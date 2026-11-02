# The only records of failing gates are matched by the blanket log ignore rule

**Severity:** medium

`custom_lint.log` and `error.log` are the sole evidence in the repository that the analyzer-plugin gate and a build attempt were failing, and both are untracked under the wildcard log rule, so neither appeared in a diff, a review, or git history. `custom_lint.log` records the analyzer-plugin failure twenty minutes before the first upgrade commit. `error.log` records an iOS build failure the following morning, after the upgrade branch had already merged, alongside the uncommitted feature work — it could not have been visible when those commits were reviewed, because it had not happened yet.

A contributor reviewing the upgrade commits on GitHub sees no trace that the analyzer-plugin gate had just failed; the evidence survives only because these particular files were not cleaned from this machine.

## Evidence

- `.gitignore:3` — `*.log`
- **`git check-ignore -v custom_lint.log error.log`** → `.gitignore:3:*.log	custom_lint.log` / `.gitignore:3:*.log	error.log`
- **`git log -1 --format=%H %ci 4fde04d`** → `4fde04dd115c89e7a7712426a29c8be087185b76 2026-07-22 20:47:45 +0100`
- `custom_lint.log` mtime `2026-07-22 20:27:20`, last entry `[custom_lint] 2026-07-22T20:27:20.128644 ... Failed to start plugins`
- `error.log` mtime `2026-07-23 08:40:21`, content stamped `2026-07-23 08:34:16.339 xcodebuild[28069:27345441] ... Failed to build iOS app` / `** BUILD FAILED **`, inside the uncommitted feature-work window (`lib/` mtimes `2026-07-23 08:37:07`–`08:59:36`)
