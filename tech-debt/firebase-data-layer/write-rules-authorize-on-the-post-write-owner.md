# Write rules never require the existing ownerID to match, only the incoming one

**Severity:** critical

Activities' write condition compares the caller's uid only against `request.resource.data.ownerID`, the merged post-write document, never against `resource.data.ownerID`, the owner the document already has. Vices ORs that same incoming-owner check with a `resource.data.ownerID` comparison, but `allow` statements OR together, so the extra branch narrows nothing: a caller who satisfies only the incoming-owner check is authorized regardless. A signed-in user who writes to another account's document ID while supplying their own uid as `ownerID` satisfies the rule for both collections, and the overwritten document is reassigned since `ownerID` is mutable by whoever wrote last.

Owner-scoped reads keep IDs from being enumerated through queries, but the app's own route scheme embeds vice and activity IDs in paths such as `/vices/:viceID/activities/:activityID`, which travel through URLs and browser history in the web build CI deploys.

## Evidence

- `firestore.rules:8` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `firestore.rules:13` — `allow write: if request.auth.uid != null && request.auth.uid == request.resource.data.ownerID;`
- `firestore.rules:7` — `allow read, write: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
- `lib/main.dart:78` — `if (uri.pathSegments.length == 4 &&`
- `lib/vice_activity_history_page.dart:65` — `'/vices/$viceID/activities/${activity.id}',`
