# Make logging work with no signal, and say so in the listing

**Priority:** v1 must-have

## What

- Configure Firestore persistence explicitly on iOS and macOS.
- Mark entries whose snapshot has `hasPendingWrites` as "not yet synced".
- Show an offline banner.
- Stop treating a write timeout as a failure, since the write is still queued (queue 1a does this for the record
  dialog, C3).

Then put "works offline" in the store copy.

## Why

- SOURCED (register): persistence is never configured; no read path checks snapshot metadata; the activity editor still
  reports a queued save as timed out; there is no connectivity indicator.
- INFERENCE: a journal is only as good as its completeness. People log where the thing happens, often with no signal,
  and a lost or doubled entry also corrupts every insight computed from it.

## Options

- **A.** Lean on Firestore's offline cache: explicit cache settings, metadata in the UI, no blocking awaits on writes.
- **B.** A local-first rewrite (SQLite as the source of truth, synced to Firestore).
- **C.** Leave it, and drop "offline" from the copy.

## Recommendation

Claude's recommendation: **A.** Firestore already queues writes offline on Apple platforms; the bugs come from the UI
waiting for the server. Test by cutting the network on a Simulator against the emulators. The on-device insight store
is separate and derived, so it needs no sync at all (see the [insights engine](../insights/insights-engine.md)).

**Effort:** M

**Revenue impact:** Indirect, through retention, reviews and insight quality.

**Depends on:**
- [`firestore-persistence-is-never-configured`](../../tech-debt/offline-and-write-reliability/firestore-persistence-is-never-configured.md)
- [`no-read-path-inspects-snapshotmetadata`](../../tech-debt/offline-and-write-reliability/no-read-path-inspects-snapshotmetadata.md)
- [`editor-reports-a-queued-save-as-timed-out`](../../tech-debt/offline-and-write-reliability/editor-reports-a-queued-save-as-timed-out.md)
- [`no-connectivity-indicator-or-retry-affordance`](../../tech-debt/offline-and-write-reliability/no-connectivity-indicator-or-retry-affordance.md)

**Needs Jack:** no
