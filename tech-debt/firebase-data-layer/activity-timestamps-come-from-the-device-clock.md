# createdAt is a server timestamp for vices and a client-clock value for activities

**Severity:** medium

`add_vice.dart` stamps a new vice with `FieldValue.serverTimestamp()`, while both activity write paths send a `DateTime` parsed from a text field, which the SDK converts using the device clock in local time. The same field therefore carries two different notions of time depending on collection, and every ordering, day bucket and range filter over activities is computed from values the client fully controls.

`firestore.rules` checks only that an activity's `createdAt` is a timestamp, never that it matches `request.time` or falls within any bound, so a skewed clock, a manually typed date or a hand-crafted write places an activity anywhere on the timeline. Editing an activity rewrites `createdAt` from the same client-parsed source.

## Evidence

- `lib/add_vice.dart:45` — `'createdAt': FieldValue.serverTimestamp(),`
- `lib/widgets/record_new_activity_dialog.dart:252` — `'createdAt': date,`
- `lib/vice_activity_editor_page.dart:104` — `'createdAt': parsedDate,`
- `firestore.rules:57` — `&& request.resource.data.createdAt is timestamp;`
