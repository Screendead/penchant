# Make logging work with no signal, and say so in the listing

**Priority:** v1 must-have

## What

- Configure Firestore persistence explicitly on every platform.
- Mark entries whose snapshot has `hasPendingWrites` as "not yet synced".
- Show an offline banner.
- Stop treating a write timeout as a failure, since the write is still queued.

Then put "works offline" in the store copy.

## Why

- SOURCED (register):
  - Persistence is never configured, and it differs between web and native.
  - No read path checks snapshot metadata.
  - The activity editor still reports a queued save as timed out.
  - There is no connectivity indicator.
- INFERENCE: people log where the activity happens (a pub, outside, on a commute), so offline is the core case, not an edge case. A lost or duplicated log is a one-star review.

## Options

- **A.** Lean on Firestore's offline cache: explicit cache settings, a UI that reads snapshot metadata, and no blocking awaits on writes. Verify the current cache API for each platform in the Firebase docs.
- **B.** A local-first rewrite (drift or sqlite as the source of truth, synced to Firestore).
- **C.** Leave it, and drop "offline" from the positioning.

## Recommendation

Claude's recommendation, not a decision: **A.** Firestore already queues writes offline on native. The bugs come from the UI waiting for server acknowledgement. Test it by toggling the network on an iOS Simulator against the emulators.

**Effort:** M

**Revenue impact:** Indirect, through retention and reviews.

**Depends on:**
- [`firestore-persistence-is-never-configured`](../../tech-debt/offline-and-write-reliability/firestore-persistence-is-never-configured.md)
- [`no-read-path-inspects-snapshotmetadata`](../../tech-debt/offline-and-write-reliability/no-read-path-inspects-snapshotmetadata.md)
- [`editor-reports-a-queued-save-as-timed-out`](../../tech-debt/offline-and-write-reliability/editor-reports-a-queued-save-as-timed-out.md)
- [`no-connectivity-indicator-or-retry-affordance`](../../tech-debt/offline-and-write-reliability/no-connectivity-indicator-or-retry-affordance.md)

**Needs Jack:** no
