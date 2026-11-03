# Let users name their own units and set a cost per unit, for spend

**Priority:** monetisation

## What

Today `Unit` is a closed six-value enum serialised by name. This adds, on each vice:

- a custom unit label (cups, mg, sessions, standard drinks), with the enum kept as presets;
- an optional cost per unit, giving "spent this week" and spend trends. An entry's own `cost` overrides it.

Decimal quantities go through the separate `amount` field in
[granular logging](../insights/granular-logging-and-data-model.md).

## Why

- SOURCED (C18): new fields on vices are allowed, so the label and the cost need no further call.
- SOURCED (code): `Unit.fromString` calls `firstWhere` with no `orElse` (`lib/data/unit.dart`), so an unknown unit
  string throws in every older build. A custom label must therefore be a new field (`unitLabel`) beside `unit`, never
  a new value in it.
- INFERENCE: spend is a neutral, non-medical fact that fits C16; "money saved" assumes cutting down and does not.

## Options

- **A.** Curated extra enum values. Breaks older clients, as above.
- **B.** `unitLabel` and `costPerUnit` on the vice, with the enum kept as presets.
- **C.** Unit conversion (units, mg, standard drinks). Conversion rules differ by country and edge toward medical
  claims.

## Recommendation

Claude's recommendation: **B.** Spend totals free, spend trends and overlays in Pro. Currency follows the device
locale, stored as an ISO code on the vice.

**Effort:** M

**Revenue impact:** Medium: spend cards are strong screenshots.

**Depends on:**
- [granular logging](../insights/granular-logging-and-data-model.md)
- [`model-parsers-cast-unconditionally`](../../tech-debt/firebase-data-layer/model-parsers-cast-unconditionally.md)
- [`value-rendering-is-english-and-locale-insensitive`](../../tech-debt/accessibility-and-localization/value-rendering-is-english-and-locale-insensitive.md)

**Needs Jack:** no
