# _updateProfile calls verifyBeforeUpdateEmail on a possibly stale session and reports partial success as failure

**Severity:** high

The method always calls `updateDisplayName`, then `verifyBeforeUpdateEmail`,
then `updatePhotoURL`, with no `reauthenticateWithCredential` anywhere in the
codebase. `updateDisplayName` needs no recent login and succeeds;
`verifyBeforeUpdateEmail` does and throws `requires-recent-login` on any
session past Firebase's short window, the common case for a returning user.

The single catch block reports the whole operation as failed and never runs
`updatePhotoURL` or the reload path, even though the display-name change has
already persisted to the Auth account. The force-unwrap on the email field is
unreachable while the validator requires a non-empty value, but it carries no
guarantee of its own if that path changes.

## Evidence

- `lib/account_settings.dart:38` — `await _user?.updateDisplayName(_displayName);
        await _user?.verifyBeforeUpdateEmail(_email!);
        await _user?.updatePhotoURL(_photoURL);`
- `lib/account_settings.dart:50` — `} catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
          ),
        );`
- **`grep -rn "reauthenticate" lib/`** → `(no matches)`
