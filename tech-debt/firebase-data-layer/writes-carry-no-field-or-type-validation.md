# Rules validate ownership and nothing else about a document's shape

**Severity:** high

Both collections' write rules test only `ownerID`; nothing constrains which fields exist, what types they hold, or that immutable fields stay put. A write can set `quantity` to a string, omit `archived`, drop `createdAt`, point `viceID` at a nonexistent vice, or add arbitrary extra fields, and it is accepted.

The client parsers cast every field unconditionally and map whole query snapshots in one pass, so a single non-conforming document throws inside the mapping function and puts the entire list into an error state rather than skipping one row. Documents that omit `archived` are also invisible to the archived equality filter, since Firestore equality never matches a document lacking the field. The seed script writes through the admin SDK, which bypasses rules entirely.

## Evidence

- `firestore.rules:7` — `allow read, write: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
- `firestore.rules:13` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `lib/data/vice.dart:31` — `archived: json['archived'] as bool,`
- `lib/data/vice_activity.dart:41` — `quantity: json['quantity'] as int,`
- `lib/data/vice_activity.dart:50` — `return ViceActivity.fromJson(id: doc.id, json: doc.data());`
- `admin/populateFirestore.js:30` — `createdAt: Timestamp.now()`
