# No Firestore rule grants delete on the activities collection

**Severity:** critical

The activities match block declares only a read rule keyed on `resource.data.ownerID` and a write rule keyed on `request.resource.data.ownerID`. Firestore leaves `request.resource` unpopulated on a delete, so that condition errors and resolves false, and no other statement covers the operation. The vices block above uses the `resource.data` form and is unaffected, so vice deletes are permitted while every activity delete comes back permission-denied.

Three call sites delete activity documents: the editor page's delete action, the per-row trash icon on the history page, and the Undo action on the record-activity snackbar. Each delete site catches `FirebaseException` and surfaces the message, so the visible result is an error banner rather than a crash.

## Evidence

- `firestore.rules:12` — `allow read: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
- `firestore.rules:13` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `lib/vice_activity_editor_page.dart:75` — `.delete();`
- `lib/vice_activity_history_page.dart:88` — `.delete();`
- `lib/widgets/record_new_activity_dialog.dart:289` — `await activityRef.delete();`
