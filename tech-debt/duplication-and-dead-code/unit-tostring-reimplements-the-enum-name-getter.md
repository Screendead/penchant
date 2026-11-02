# Unit.toString and Unit.fromString re-derive what .name already returns

**Severity:** low

`toString` is overridden to strip the `Unit` prefix by string splitting, duplicating what the built-in `name` getter returns.

The same file already uses that getter for the singular label, and `fromString` re-derives the value through the toString-and-split trick rather than matching against `name` directly.

## Evidence

- `lib/data/unit.dart:18` — `String toString() {\n    return super.toString().split('.').last;\n  }`
- `lib/data/unit.dart:23` — `static Unit fromString(String unit) {\n    return Unit.values.firstWhere(\n      (e) => e.toString().split('.').last == unit,\n    );\n  }`
