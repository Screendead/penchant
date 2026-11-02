# The seed script writes vices without the archived field the client requires

**Severity:** high

`admin/populateFirestore.js` writes vice documents carrying only `name`, `unit`, `ownerID` and `createdAt`. `Vice.fromJson` performs a non-nullable cast of `json['archived']`, which throws a runtime type error whenever the field is absent.

Git history shows the script was last touched on 2024-08-05, nine days before `archived` was added to the model, and has never been revisited. Running the seed command documented in CLAUDE.md therefore produces data that breaks any Dart path reading it back.

## Evidence

- `admin/populateFirestore.js:26` — `const docRef = await vicesRef.add({`
- `admin/populateFirestore.js:27` — `name: vice.name, unit: vice.unit, ownerID: ownerID, createdAt: Timestamp.now()`
- `lib/data/vice.dart:31` — `archived: json['archived'] as bool,`
- **`git log --format="%h %ad %s" --date=short -- admin/populateFirestore.js`** → `29b6729 2024-08-05 Update unit for Video Games vice to hour`
- **`git log --format="%h %ad %s" --date=short --follow -- lib/data/vice.dart`** → `4489c50 2024-08-14 Add archived field to Vice class`
