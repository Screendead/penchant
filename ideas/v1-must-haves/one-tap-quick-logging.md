# Log an activity in one tap from Today

**Priority:** v1 must-have

## What

Today, logging goes through the modal "Record New Vice Activity" dialog: a vice dropdown, a date field with a timer and lock toggle, and a quantity field. Replace that with a tile for each unarchived vice on Today:

- **Tap:** logs the vice's default quantity (for example 1 drink or 15 minutes), with a working Undo snackbar.
- **Long-press:** opens the full editor for a custom quantity or a backdated time.

The dialog stays for edits and backfill.

## Why

- INFERENCE: logging friction is the main reason trackers die. A log takes about five interactions plus the keyboard today, and a tile takes one. In-the-moment logs are also more accurate than ones reconstructed at bedtime.
- SOURCED (Jack): the snackbar Undo is broken on exactly this path.
- SOURCED (register): the record action disappears on the Graph tab.

## Options

- **A.** Tiles on Today: tap logs +1, long-press opens the editor.
- **B.** Keep the dialog, but preselect the last-used vice and focus the quantity field.
- **C.** A floating "+" that opens a bottom sheet of per-vice chips.

## Recommendation

Claude's recommendation, not a decision: **A.** It is the biggest daily-use improvement, and it reuses the existing write path. Ship it after the activity-delete rule fix, because Undo is a delete. Widgets, Shortcuts and reminders later reuse the same "log one" action.

**Effort:** M

**Revenue impact:** High, through retention.

**Depends on:**
- [`activity-deletes-permitted-by-no-rule`](../../tech-debt/firebase-data-layer/activity-deletes-permitted-by-no-rule.md)
- [`record-action-disappears-on-the-graph-tab`](../../tech-debt/navigation-and-unreachable-ui/record-action-disappears-on-the-graph-tab.md)
- [`writes-bypass-providers-with-inline-firestore-calls`](../../tech-debt/widget-state-and-view-logic/writes-bypass-providers-with-inline-firestore-calls.md)
- [per-vice goals](per-vice-goals-and-limits.md), for where the default quantity lives

**Needs Jack:** no
