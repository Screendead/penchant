# Every mutation is an inline FirebaseFirestore call that restates the document contract

**Severity:** high

There is no repository or write layer: each mutation is an inline `FirebaseFirestore.instance` call embedded in a widget callback that restates by hand the field names, the `ownerID` rule, the `archived` default and the `createdAt` type the data classes already declare. The identity source differs by site, with `add_vice` taking `uid` from `userProvider` and the record dialog from the `FirebaseAuth` singleton, and the `createdAt` type differs too, a server timestamp in one place and a raw local `DateTime` in two others.

The literal `'archived'` appears in the model, in both manage_data writes and in the unarchived provider's where clause. Auth mutations in settings, sign_in, register and account_settings follow the same pattern, none of them passing through `userProvider`.

## Evidence

- `lib/add_vice.dart:41` — `await FirebaseFirestore.instance.collection('vices').add({`
- `lib/add_vice.dart:46` — `'archived': false,`
- `lib/widgets/record_new_activity_dialog.dart:251` — `await activityRef.set({`
- `lib/vice_activity_editor_page.dart:103` — `.update({`
- `lib/manage_data.dart:112` — `'archived': true,`
- `lib/settings.dart:54` — `FirebaseAuth.instance.signOut();`
