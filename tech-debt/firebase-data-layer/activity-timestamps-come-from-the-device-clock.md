# createdAt is a server timestamp for vices and a client-clock value for activities

**Severity:** medium

`TrackerWrites.addVice` stamps a new vice with `FieldValue.serverTimestamp()`, while `recordActivity` and `updateActivity` send the `DateTime` each screen hands them, parsed from a text field, which the SDK converts using the device clock in local time. The same field therefore carries two different notions of time depending on collection, and every ordering, day bucket and range filter over activities is computed from values the client fully controls.

`firestore.rules` checks only that an activity's `createdAt` is a timestamp, never that it matches `request.time` or falls within any bound, so a skewed clock, a manually typed date or a hand-crafted write places an activity anywhere on the timeline. Editing an activity rewrites `createdAt` from the same client-parsed source.

Switching "now" entries to a server timestamp breaks offline logging. A document whose `createdAt` is a pending server timestamp matches no `createdAt` range query until the server acknowledges it, so the entry is missing from Today for as long as the device is offline. And the server stamps the time it received the write, so an entry logged offline lands on the day it synced.

## Evidence

- `lib/writes/tracker_writes.dart:26` — `'createdAt': FieldValue.serverTimestamp(),`
- `lib/writes/tracker_writes.dart:51` — `'createdAt': createdAt,`
- `lib/widgets/record_new_activity_dialog.dart:121` — `createdAt: date,`
- `lib/vice_activity_editor_page.dart:124` — `'createdAt': dateFormat.parse(dateController.text),`
- `firestore.rules:68` — `&& request.resource.data.createdAt is timestamp`
- Firestore JS SDK 12.19.0 against the emulator, 2026-11-04: offline, a `serverTimestamp()` write showed in an `ownerID`-only query but not in the Today query (`createdAt >=` and `<` today); a client `Date` write showed in both. Once back online, the first showed only after the server acknowledged it.
- firebase.google.com/docs/firestore/manage-data/add-data — a server timestamp "tracks when the server receives the update"
