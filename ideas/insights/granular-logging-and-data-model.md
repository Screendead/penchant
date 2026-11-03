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
| `triggers` | activity | path strings | See [trigger tagging](trigger-tagging.md) |
| `with`, `place` | activity | small enums | Alone / partner / friends / colleagues; home / work / out / travelling. No GPS |
| `moodBefore`, `urge` | activity | 1–5, optional | How it felt going in |
| `cost` | activity | number, optional | Overrides the vice's cost per unit |
| `note` | activity | string ≤ 500 | Free text |
| `source` | activity | enum | manual / quick / widget / shortcut, for data-quality weighting |
| `category` | vice | enum | alcohol / caffeine / nicotine / cannabis / screen / gambling / food / other: maps a vice to HealthKit types and to sensible defaults |
| `defaultQuantity`, `unitLabel`, `costPerUnit` | vice | | [quick logging](../v1-must-haves/one-tap-quick-logging.md), [units and cost](../monetisation/units-and-cost-per-unit.md) |
| `schemaVersion` | both | int | Which migrations a document has had |

The [check-in](../v1-must-haves/evening-check-in-and-reminders.md) adds a per-day record of "nothing to log".

## Decision so far

Decided by Jack 2026-11-03 (C18): **new fields on vices are allowed**; optional ones freely, mandatory ones only with
a migrator that runs on first launch and adds them to existing records. C18 does not cover fields on `activities` or
new collections (`days`, `triggerNodes`), which most of the table needs.

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
- [`activity-timestamps-come-from-the-device-clock`](../../tech-debt/firebase-data-layer/activity-timestamps-come-from-the-device-clock.md)
- [`day-windows-use-device-local-midnight`](../../tech-debt/firebase-data-layer/day-windows-use-device-local-midnight.md)

**Needs Jack:** yes — Extend C18 to fields on `activities` and to the new `days` and `triggerNodes` collections, and
allow decimals through a separate `amount` field?
