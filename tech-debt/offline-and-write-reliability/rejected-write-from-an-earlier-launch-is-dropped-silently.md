# A queued change the server refuses after the app restarts vanishes without a word

**Severity:** medium

A change the server refuses after `settleWrite` has called it queued is named in the rejected-writes banner, but
only while the app that made it is still running: the banner hears of the refusal through the write's Dart future.
The on-device cache keeps queued writes across restarts and the SDK sends them once it reconnects, so a change made
offline, with the app closed or killed before the device reconnects, has no future left to listen to. If the server
then refuses it (the rules changed, or the activity's vice was deleted from another device), the SDK drops it from
the cache and listeners redraw without it. The entry disappears, its "Not yet synced" mark goes with it as if it had
synced, and no message is shown. No write path offers a retry either.

## Evidence

- `lib/writes/settle_write.dart`: the refusal reaches `onRejectedLater` through a listener on the write's future,
  which exists only in the process that made the write.
- `lib/firebase_init.dart`, `_configureFirestoreCache`: persistence is on in production, so queued writes outlive
  the process.
- FirebaseFirestoreInternal 12.19.3, `Firestore/core/src/core/sync_engine.cc`: `SyncEngine::HandleRejectedWrite`
  calls `local_store_->RejectBatch(batch_id)`, which removes the mutation, then `NotifyUser`, whose comment reads
  "Mutations restored from persistence won't have callbacks", then `EmitNewSnapshotsAndNotifyLocalStore`, which
  redraws listeners without it.
