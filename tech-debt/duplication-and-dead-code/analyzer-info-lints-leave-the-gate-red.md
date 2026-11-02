# flutter analyze exits nonzero on two info-level lints, both in the working-tree rewrite

**Severity:** low

The run reports an `unnecessary_underscores` info in the new history page's `separatorBuilder` and an `unnecessary_getters_setters` info on `ViceTracker`'s selected-date pair, and exits 1, so automation gating on the exit code fails on cosmetic input.

The getter and setter pair is a direct leftover of the chart rewrite: the setter previously pushed the new date into `ViceChartState` through a `GlobalKey`, and with that plumbing removed its body is a bare field assignment. CLAUDE.md documents `flutter analyze` as a command without noting that it is not currently clean.

## Evidence

- **`flutter analyze --no-pub`** → `info • Unnecessary use of multiple underscores. Try using '_' • lib/vice_activity_history_page.dart:52:37 • unnecessary_underscores`
- **`flutter analyze --no-pub`** → `2 issues found. (ran in 4.2s)\nEXIT_CODE:1`
- `lib/vice_activity_history_page.dart:52` — `separatorBuilder: (_, __) => const SizedBox(height: 8),`
- **`flutter analyze --no-pub`** → `info • Unnecessary use of getter and setter to wrap a field. Try removing the getter and setter and renaming the field • lib/vice_tracker.dart:19:16 • unnecessary_getters_setters`
- `lib/vice_tracker.dart:18` — `late DateTime _selectedDate;\n  DateTime get selectedDate => _selectedDate;\n  set selectedDate(DateTime value) {\n    _selectedDate = value;\n  }`
