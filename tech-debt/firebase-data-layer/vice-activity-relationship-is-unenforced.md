# Legacy activities whose vice is gone or foreign appear on no screen

**Severity:** low

`firestore.rules` requires a new activity's `viceID` to name a vice its writer owns, and updates cannot change `viceID`, but activities written before that rule may still carry a `viceID` matching no vice or another account's vice. The app has never deleted a vice except through account deletion, which removes activities first, so such rows come only from writes made outside the app. Export reads every activity by `ownerID` alone, so it includes them, and Delete account removes them. But the Today query fetches them for their day and the dial and tallies drop them, every other activity query constrains `viceID`, and the editor refuses an activity whose `viceID` differs from its route, so no screen shows one or deletes it on its own.

## Evidence

- `lib/providers/vice_activity_day_provider.dart:17` — `.where('ownerID', isEqualTo: uid)`
- `lib/vice_tracker.dart:144` — `if (byID[a.viceID] case final Vice vice)`
- `lib/vice_activity_editor_page.dart:213` — `(found != null && found.viceID == widget.viceID)`
- `lib/account/account.dart:47` — `_ownedCollections = <String>['activities', 'vices']`, read and deleted by `ownerID` alone
