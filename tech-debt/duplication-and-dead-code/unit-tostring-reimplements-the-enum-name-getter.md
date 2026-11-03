# Unit.toString re-derives what .name already returns

**Severity:** low

`toString` is overridden to strip the `Unit` prefix by string splitting, duplicating what the built-in `name` getter returns.

The same file already uses that getter for the singular label and in `fromString`.

## Evidence

- `lib/data/unit.dart:19` — `String toString() {\n    return super.toString().split('.').last;\n  }`
- `lib/data/unit.dart:13` — `String get singular => name;`
