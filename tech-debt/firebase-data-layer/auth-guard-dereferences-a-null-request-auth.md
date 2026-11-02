# All four allow statements guard on request.auth.uid rather than request.auth

**Severity:** low

For an unauthenticated request `request.auth` is itself null, so the guard dereferences null, the evaluation errors, and the statement resolves false. The outcome is a correct denial, but correctness rests on the engine swallowing an error rather than on the condition as written. The intended null check is on `request.auth`.

## Evidence

- `firestore.rules:7` — `allow read, write: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
- `firestore.rules:12` — `allow read: if request.auth.uid != null && request.auth.uid == resource.data.ownerID;`
