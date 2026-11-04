# Offer one optional daily check-in that closes the day's journal

**Priority:** v1 must-have

## What

Give Settings a Notifications row (it had one that dead-ended on a 404, since removed) for local notifications, off
by default:

- An evening check-in at a time the user picks ("Anything to add to today?"), with two actions: "Nothing to log
  today" and "Add an entry".
- Nudges toward a limit only for vices with an [optional goal](../growth-later/optional-goals-and-limits.md).

The permission is asked only when the user turns the check-in on. Copy is neutral (C16) and respects
[discreet mode](../growth-later/app-lock-and-discreet-mode.md).

## Why

- INFERENCE: a check-in is the cheapest retention lever for journals, and it fixes a data gap the insights care about:
  the app cannot tell "nothing happened" from "forgot to log". A day the user confirmed as empty is a real zero; an
  unconfirmed day is missing data, and the [insights engine](../insights/insights-engine.md) should treat it so.
- SOURCED (C12): a new activity's quantity must be greater than 0, so "nothing today" can no longer be a zero-quantity
  activity. It needs its own record.

## Options

- **A.** A `days` collection: one document per user per local date (`ownerID`, `date`, `confirmed`, optional note),
  written by the check-in. A new collection, with rules and tests.
- **B.** A `confirmedThrough` date on the user's profile. One field, but no per-day note and no gaps.
- **C.** No check-in in 1.0; Settings stays without a Notifications row.

## Recommendation

Claude's recommendation: **A, free, in 1.0.** Per-day confirmation is what lets the engine count a zero, and the same
document can later carry a daily mood or note. It sits outside C18 (which covers fields on vices), so it needs Jack's
yes.

**Effort:** M

**Revenue impact:** Medium to high, through retention and insight quality.

**Depends on:** [quick logging](one-tap-quick-logging.md); the day rule (`CLAUDE.md`, **Days**).

**Needs Jack:** yes — May "nothing logged today" be a new `days` collection?
