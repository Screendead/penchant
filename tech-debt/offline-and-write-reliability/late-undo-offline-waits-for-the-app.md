# A late Undo made offline from a widget reaches the server only when Penchant next starts

**Severity:** low

A widget or menu bar Undo past the 7 s hold queues a delete. A background flush keeps an unacknowledged log queued
for its next run, but lets an unacknowledged delete leave the queue: the SDK's queued copy would reach the server
first, and the rules refuse a repeat delete, so a second send would be reported as "Not undone". The delete then
sits only in the SDK queue of the exited process, so other devices show the entry until Penchant next starts, in
either mode.

## Evidence (at `feat/mac-widget-sync-now`, 2026-11-08)

- `lib/widget_bridge/log_queue.dart:95` — `return acknowledged || !inBackground || !creates`
- `tests/firestore-rules/rules.test.js:803` — `// resource is null, so ownsExisting() cannot hold: a repeat delete is denied, not a no-op.`
