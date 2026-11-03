# Legacy activities whose vice is gone or foreign are fetched but reachable from no screen

**Severity:** low

`firestore.rules` requires a new activity's `viceID` to name a vice its writer owns, and updates cannot change `viceID`, but activities written before that rule may still carry a `viceID` matching no vice or another account's vice. The Today query filters on owner and date only, so it fetches such rows for their day and the chart drops them; every other activity query constrains `viceID`, and the editor refuses an activity whose `viceID` differs from its route. No screen lists them, so their owner can neither see nor delete them.

## Evidence

- `lib/providers/vice_activity_day_provider.dart:17` — `.where('ownerID', isEqualTo: key.uid)`
- `lib/vice_chart.dart` — `if (quantity != null) {`
- `lib/vice_activity_editor_page.dart:172` — `if (vice == null || activity == null || activity.viceID != widget.viceID) {`
