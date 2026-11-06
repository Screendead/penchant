# Tag what led to each entry, from a tree that learns your common triggers

**Priority:** insights (capture in 1.0)

## What

After a log, the detail sheet offers triggers:

- **Top level**, a short fixed list: Social, Feeling, Work, Body, Routine, Place, Craving, Other.
- **Drill-down:** each opens more specific options (Work → Meeting → 1:1 / Large / Presenting; Feeling → Stressed →
  Deadline / Conflict). Tapping any level records it; going deeper is optional.
- **Memory:** your most common and most recent triggers for this vice sit above the tree as one-tap chips, ranked by
  frequency with a recency decay and by time of day. Computed on the device from your history, so nothing extra is
  stored.
- **Free text** at any level. A free-text trigger used three times is offered as a permanent node in your tree.
- Several triggers per entry; an "urge, didn't log" entry type comes later if wanted.

## Why

- SOURCED (C15): Jack wants triggers "picked from options that get more specific as you click through, remembering
  your most common ones, or free text".
- SOURCED ([Bearable](https://bearable.app/support/howto/the-factor-effect-report/),
  [Apple State of Mind](https://support.apple.com/guide/iphone/log-your-state-of-mind-iph6a6decb13/ios)): competitors
  use flat tag lists ("Associations", factors). INFERENCE: a tree gives specific answers without a long list, and a
  path such as `work/meeting/1:1` rolls up, so insights can report at whichever level has enough data.
- INFERENCE: triggers cannot be backfilled, unlike Health and Calendar history, so capture must ship in 1.0 even
  though the analysis is Pro in 1.1.

## Data

Shipped (r2-triggers A, part 1): the optional `triggers` field, its rules and parser, and the starter tree in
`lib/data/trigger_tree.dart`. Free text is stored as the label itself for now; `triggerNodes` is not built.

- On `activities`: `triggers`, an array of path strings (`"work/meeting/1:1"`, `"custom/<id>"`), optional.
- Custom nodes: a per-user `triggerNodes` collection (`ownerID`, `parentPath`, `label`, `createdAt`), so a renamed
  label renames everywhere. The built-in tree ships in the app and is versioned there.
- Both are outside C18, which covers fields on `vices`; see [granular logging](granular-logging-and-data-model.md).

## Options

- **A.** The tree, memory and free text as above.
- **B.** A flat, user-editable tag list (the Bearable model).
- **C.** Free text only, clustered later on the device.

## Recommendation

Claude's recommendation: **A, in 1.0, free.** Capture is free because it is the journal; the analysis of triggers is
Pro. Show Jack the top two levels of the starter tree as part of the pitch.

**Effort:** M

**Revenue impact:** High, indirectly: it is the raw material for the "what causes use" insights Pro sells.

**Depends on:** [quick logging](../v1-must-haves/one-tap-quick-logging.md); [granular logging](granular-logging-and-data-model.md).

**Needs Jack:** yes — Approve the starter tree's wording, and the new activity field and `triggerNodes` collection.
