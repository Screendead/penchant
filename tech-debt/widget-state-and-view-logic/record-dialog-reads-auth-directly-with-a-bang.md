# The record dialog takes the owner id from the FirebaseAuth singleton with a null assertion

**Severity:** medium

Every other identity read in the app goes through `userProvider`, but the activity write reads the uid inline from `FirebaseAuth.instance.currentUser` with a bang. That is a second, non-reactive source of truth for who is signed in, and the null assertion throws if the session ends between opening the dialog and pressing Record.

The resulting error is neither a `FirebaseException` nor a `TimeoutException`, so neither catch clause in that method handles it.

## Evidence

- `lib/widgets/record_new_activity_dialog.dart:253` — `'ownerID': FirebaseAuth.instance.currentUser!.uid,`
- `lib/widgets/record_new_activity_dialog.dart:260` — `} on FirebaseException catch (e) {`
- `lib/add_vice.dart:44` — `'ownerID': user.uid,`
