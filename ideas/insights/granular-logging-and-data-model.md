# Log each entry at maximum granularity, and grow the data model without breaking old clients

**Priority:** insights (capture in 1.0)

## What

Every entry can carry, beyond vice, quantity and time:

| Field | On | Type | Why |
|---|---|---|---|
| `createdAt` (exists) | activity | timestamp | When it happened; already editable, so it is the event time |
| `loggedAt` | activity | server timestamp | When it was written: tells live logs from evening backfill, whose times are less reliable |
| `timeZone` | activity | IANA name | Day and hour-of-day stay right when travelling |
| `durationMinutes` | activity | int, optional | Sessions (screen time, gambling, a night out) |
| `triggers` | activity | path strings | SHIPPED (picker in the record dialog and editor, `lib/data/trigger_tree.dart`, history rows); free text is stored as the label |
| `with`, `place` | activity | small enums | Alone / partner / friends / colleagues; home / work / out / travelling. No GPS |
| `moodBefore`, `urge` | activity | 1–5, optional | How it felt going in |
| `cost` | activity | number, optional | Overrides the vice's cost per unit |
| `note` | activity | string ≤ 500 | Free text |
| `source` | activity | enum | manual / quick / widget / shortcut, for data-quality weighting |
| `category` | vice | enum | SHIPPED without `screen`: alcohol / caffeine / nicotine / cannabis / food / gambling / other (`lib/data/category.dart`), with a migrator that guesses it for older vices |
| `defaultQuantity`, `unitLabel`, `costPerUnit` | vice | | `defaultQuantity` is a constant 1 (`lib/writes/log_one.dart`) and is not stored per vice; [units and cost](../monetisation/units-and-cost-per-unit.md) |
| `schemaVersion` | both | int | Which migrations a document has had |

A day with nothing logged counts as clean (`r2-days`), so there is no per-day record of "nothing to log".

## Decision so far

Decided by Jack 2026-11-06 (`r2-data-model`): **B**, optional fields plus a first-launch migrator, with decimals
through a separate optional `amount` beside `quantity`. The `amount` field has shipped (rules, parser, record dialog,
editor, export); the other fields and the migrator have not.

Decided by Jack 2026-11-03 (C18): **new fields on vices are allowed**; optional ones freely, mandatory ones only with
a migrator that runs on first launch and adds them to existing records. C18 does not cover fields on `activities` or
new collections (`days`, `triggerNodes`), which most of the table needs.

## Left from the shipped ideas

The one-tap log (tally `+`, Log-fan tap, 8-second Undo), trigger tagging (tree, usual chips, "Your own" chips) and the
sealed journal fields are built. What remains of them:

- The detail sheet after a one-tap log, once the context fields above exist.
- `triggerNodes`, so custom triggers and their counts follow the user to another device (the counts live in
  shared_preferences per uid today), and time-of-day weighting of the usual chips.
- An "urge, didn't log" entry type, if wanted. The analysis of triggers belongs to the
  [insights engine](insights-engine.md).

## Consequences

- SOURCED (`firestore.rules`): create fixes each collection's field set, so every field needs a rules change and
  tests. SOURCED (C1): CI deploys rules on merge, so a new rule is live before any user has the build that writes it.
- INFERENCE: **old clients keep writing.** The live web build (until hosting is disabled), and every older TestFlight
  or store build, creates documents without the new fields. If the rules required a field, those writes would start
  failing with permission errors. So every new field must stay optional in the rules for as long as an old client
  exists; "mandatory" can only mean "always present in the app's model", filled by the parser's default or the
  migrator.
- SOURCED (code): `Vice.fromJson` and `ViceActivity.fromJson` read named keys and ignore the rest, so old clients
  tolerate added fields. Builds before the parser change cast unconditionally; the current build reads every field
  through `lib/data/json_fields.dart`, which defaults a missing or mistyped value, so each new field needs a default
  there too.
- SOURCED (code): builds before the parser change parse `quantity` `as int`; the current build rounds a double to the
  nearest int (`readInt`). INFERENCE: writing `1.5` crashes every older client that reads it, and the current one
  reads it as 2, so decimals cannot go into `quantity` while old clients exist.
- INFERENCE: the migrator is a client loop over the user's own documents with batched updates, idempotent and keyed
  on `schemaVersion`; it costs one write per document per migration and must survive being killed half way.
- INFERENCE: the on-device insight store never migrates. It is derived, so a new engine version drops and rebuilds it
  (see the [insights engine](insights-engine.md)).

## Options

- **A. Optional everywhere:** every new field optional in rules and model, with parser defaults. No migrator.
- **B. A, plus mandatory-in-model fields** filled by a first-launch migrator where no default can be inferred (for
  example asking the user each vice's `category` once, then writing it).
- **C. Decimals now** through a new optional `amount` (number) beside `quantity` (an int, rounded up so C12 holds),
  read in preference by new clients.

## Recommendation

Claude's recommendation: **B and C, in this order:** first a build whose parsers default every missing field (the code
is in; it must ship before any new field is written), then the fields in one rules PR with tests, then the migrator for `category` only. Keep
everything optional in the rules until the web site is down and no pre-1.0 build is in use.

**Effort:** M (the fields, rules and tests) plus S per migration

**Revenue impact:** High, indirectly: every insight is only as good as these fields.

**Depends on:**
- the device clock stamps `createdAt` (`r4-server-time`, Jack, 2026-11-06)
- the day rule (`CLAUDE.md`, **Days**): an entry counts on the viewing device's local day, and its zone is not stored

**Needs Jack:** no (decided 2026-11-06, above).
