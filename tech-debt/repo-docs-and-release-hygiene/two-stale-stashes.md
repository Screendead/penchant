# Both stashes were superseded within minutes or years and cannot be usefully applied

**Severity:** medium

The newer stash, from 2026-07-22, was created eight minutes before a commit covering nearly the same file set that evening, and HEAD has diverged further since, notably an `ios/Podfile` whose static-linkage and 15.0 platform pins the stash predates entirely. The older one, from 2025-06-27, only removes debug print calls from `vice_chart.dart` that are already absent from HEAD.

Both sit unaddressed in the stash list, one over a year old, on branches that are themselves already merged and stale.

## Evidence

- **`git stash list`** → `stash@{0}: On manage-data: wip-ios-fix-manage-data-before-combine` / `stash@{1}: WIP on add-time-graph: 189c8c3 No need for that argument`
- **`git log -g --date=iso`** → `HEAD@{2026-07-22} 2026-07-22 20:20:01 +0100 commit: Fix iOS device build and keep archived-vices branch compatible`
- **`git diff stash@{0} -- ios/Podfile`** → `-platform :ios, '13.0'` / `+platform :ios, '15.0'` / `-  use_modular_headers!` / `+  use_frameworks! :linkage => :static`
- **`git stash show -p stash@{1}`** → `-    print('Vices:');` / `-    vices.forEach((Vice vice) { print(vice.name); });`
