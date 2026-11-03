# Log in one tap, then add detail without being made to

**Priority:** v1 must-have

## What

Today a log goes through the modal "Record New Vice Activity" dialog: a vice dropdown, a date field with a timer and a
lock toggle, and a quantity field. Replace that, for the common case, with a tile per unarchived vice on Today:

- **Tap:** logs the vice's default quantity at the current time, and shows a sheet offering the detail fields
  (triggers, context, note). Dismissing the sheet keeps the entry; the detail can be added later from the timeline.
- **Long-press:** opens the full editor for another quantity or a backdated time.

Undo stays 8 seconds (C4). The dialog stays for edits and backfill.

## Why

- INFERENCE: friction is what kills trackers, and in-the-moment logs are more accurate than ones rebuilt at bedtime.
  Maximum granularity (C15) pulls the other way: the answer is to capture the time instantly and ask for the rest
  without blocking.
- SOURCED (register): the record action disappears on the Graph tab.

## Options

- **A.** Tiles on Today; tap logs and offers the detail sheet; long-press opens the editor.
- **B.** Keep the dialog, preselect the last-used vice and focus quantity.
- **C.** A floating "+" opening a sheet of per-vice chips.

## Recommendation

Claude's recommendation: **A.** It reuses the write path, and widgets, Shortcuts and reminders later reuse the same
"log one" action. The detail sheet is the [trigger picker](../insights/trigger-tagging.md) plus the
[context fields](../insights/granular-logging-and-data-model.md).

**Effort:** M

**Revenue impact:** High, through retention and through richer data for the insights Pro sells.

**Depends on:**
- [`record-action-disappears-on-the-graph-tab`](../../tech-debt/navigation-and-unreachable-ui/record-action-disappears-on-the-graph-tab.md)
- [granular logging](../insights/granular-logging-and-data-model.md), for where the default quantity lives

**Needs Jack:** no
