# Roughly 1,367 lines across twelve paths are uncommitted, unpushed, and six of them untracked

**Severity:** critical

Six tracked files carry 340 changed lines and six new files add 1,027 more, none of it in any commit, stash, or remote. File mtimes put the bulk of this work at 2026-07-23, weeks before this catalogue was assembled. The delta spans four distinct features: a two-tab Homepage with a new usage line chart, a rewrite of the today radar chart onto a per-day query, a history page plus an activity editor wired into `onGenerateRoute`, and a rewritten record-dialog submit path with a loading overlay and an Undo snackbar.

`dart analyze` reports no errors against this code — its two findings are the info-level lints catalogued in [duplication-and-dead-code](../duplication-and-dead-code/analyzer-info-lints-leave-the-gate-red.md) — so it reads as finished work rather than a scratch experiment. Because six of the paths are untracked, the work is invisible to `git diff`, would not survive a plain `git stash`, and has never been reviewed. It exists on one machine.

## Evidence

- **`git diff --stat`** → `6 files changed, 228 insertions(+), 112 deletions(-)`
- **`git status --porcelain`** → `?? CLAUDE.md`, `?? lib/providers/vice_activity_day_provider.dart`, `?? lib/providers/vice_activity_history_provider.dart`, `?? lib/usage_graph_view.dart`, `?? lib/vice_activity_editor_page.dart`, `?? lib/vice_activity_history_page.dart`
- **`ls -la lib/vice_tracker.dart lib/homepage.dart lib/main.dart`** → `2026-07-23 08:37:56 lib/vice_tracker.dart` ... `2026-07-23 08:38:03 lib/main.dart`
- **`git merge-base --is-ancestor HEAD origin/master && echo ...`** → `HEAD IS ANCESTOR OF origin/master`
- **`dart analyze lib`** → `2 issues found.`
