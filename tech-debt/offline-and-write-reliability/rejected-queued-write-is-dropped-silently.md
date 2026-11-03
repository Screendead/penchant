# A change made offline that the server later refuses vanishes without a word

**Severity:** high

Every write path waits up to ten seconds for the server through `settleWrite`, and after that tells the user the
change is saved on the device and will sync. From then on nothing listens to the write. If the server refuses it once
the device reconnects (the rules changed, or the activity's vice was deleted from another device so the ownership
`get()` fails), the SDK drops the change from its local cache and listeners redraw without it. The entry or
edit disappears, its "Not yet synced" mark goes with it as if it had synced, and no message is shown. No write path
offers a retry either.

This covers the record dialog, its Undo, the editor's save and delete, the history page's delete, Add Vice, and
archive and unarchive.

## Evidence

- `lib/writes/settle_write.dart`: `settleWrite` returns false on `TimeoutException` and keeps no reference to `write`.
- Dart SDK `lib/async/future_impl.dart`, `_Future.timeout`: once the timer has fired, a later error from the source
  future is discarded (`onError: ... if (timer.isActive)`).
- FirebaseFirestoreInternal 12.15.0, `Firestore/core/src/core/sync_engine.cc`, `SyncEngine::HandleRejectedWrite`:
  `local_store_->RejectBatch(batch_id)` removes the mutation, `NotifyUser` fails the write's future, and
  `EmitNewSnapshotsAndNotifyLocalStore` redraws listeners without it.
