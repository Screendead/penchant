# The date-navigation Row lays out four unconstrained children with no Flexible

**Severity:** medium

A calendar icon, a Today or days-ago label, a separator `CircleAvatar` and a `DropdownButton` whose menu items are full strings such as "Wednesday, September 30, 2026" are all direct `Row` children under `space-evenly` alignment with no `Expanded` or `Flexible`.

At larger text scale their combined intrinsic width exceeds the 600px-constrained column and the row overflows horizontally.

## Evidence

- `lib/vice_tracker.dart:80` — `Row(\n                mainAxisAlignment: MainAxisAlignment.spaceEvenly,`
- `lib/vice_tracker.dart:114` — `DateFormat('EEEE, MMMM d, yyyy').format(date);`
