# Let users define their own units and a cost per unit, for "money saved"

**Priority:** monetisation

## What

Today `Unit` is a closed six-value enum serialised by its name, and quantity is an `int`. This proposal adds:

- a custom unit label (cups, units, mg, sessions);
- an optional cost per unit on each vice, which gives "spent this month" and "saved against your baseline".

Separately, it allows fractional quantities such as half a drink.

## Why

- SOURCED ([market scan](../market-scan.md)): MyDrinkaware tracks spend, and quit trackers lead with money saved. INFERENCE: money is the most motivating and least preachy metric, and it carries no medical claim.
- SOURCED (code): `Unit.fromString` calls `firstWhere` with no `orElse` (`lib/data/unit.dart:24`), so an unknown unit string crashes the parser on every older build. Quantity is parsed with `int.parse` (`lib/widgets/record_new_activity_dialog.dart:245`).
- Standing rule: the documented shape must stay, and a change from `int` to `num` for quantity alters it.

## Options

- **A.** Extend the enum with curated values (cup, gram, mg, standard drink, serving), and allow decimal quantities.
- **B.** A free-text unit label plus an optional cost per unit, stored on the vice, with the enum kept as presets and as a fallback.
- **C.** Full unit conversion (units, mg, standard drinks).

## Recommendation

Claude's recommendation, not a decision: **B, in sequence.**

1. Ship a build whose parser tolerates unknown units and missing fields.
2. Then add the label and the cost.

Show spend for free, and make "saved against baseline" and spend history Pro. Treat fractional quantity as a separate data-shape question. Skip C: standard-drink conversion differs by country and edges towards medical claims.

**Effort:** M

**Revenue impact:** Medium. Money-saved cards make strong screenshots and drive retention, and the history is a Pro hook.

**Depends on:**
- [per-vice goals](../v1-must-haves/per-vice-goals-and-limits.md)
- [`model-parsers-cast-unconditionally`](../../tech-debt/firebase-data-layer/model-parsers-cast-unconditionally.md)
- [`writes-carry-no-field-or-type-validation`](../../tech-debt/firebase-data-layer/writes-carry-no-field-or-type-validation.md)
- [`value-rendering-is-english-and-locale-insensitive`](../../tech-debt/accessibility-and-localization/value-rendering-is-english-and-locale-insensitive.md)

**Needs Jack:** yes — Should currency follow the device locale or be a single currency in v1, and may quantity change from `int` to `num`?
