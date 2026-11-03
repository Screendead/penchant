# No deletion or export capability, and a deleted Auth account leaves its documents unreachable forever

**Severity:** medium

Nothing under `lib/` offers account deletion or a data download, despite two
owner-scoped collections holding personal behavioural-tracking data.
The repository has no Cloud Functions, so there is no auth `onDelete` trigger
or any other server-side hook that could remove a user's documents.

Firebase never reissues a UID, so vices and activities whose `ownerID` points
at a deleted account can never again be matched by any live user, yet remain
stored indefinitely with no admin tooling in the repository to find or purge
them; `populateFirestore.js` is a one-off seeder, not a lifecycle tool.

## Evidence

- **`grep -rn "deleteUser\|reauthenticate" lib/`** → `(no matches)`
- `lib/settings.dart:22` — `ListTile(
              title: const Text('Account'),
              leading: const Icon(Icons.account_circle),
              onTap: () {
                Navigator.of(context).pushNamed('/settings/account');
              },
            ),`
