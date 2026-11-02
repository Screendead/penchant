# The same nullable id-lookup idiom is written out independently in three places

**Severity:** low

The pattern that tests a `where` clause for emptiness and otherwise calls `firstWhere` appears twice in the editor page and once in the history page.

Each copy exists to make an id lookup nullable, and none of the three is factored into a shared helper.

## Evidence

- `lib/vice_activity_editor_page.dart:145` — `final Vice? vice = viceList.where((Vice item) => item.id == widget.viceID).isEmpty`
- `lib/vice_activity_editor_page.dart:148` — `final ViceActivity? activity = activityList.where((ViceActivity item) => item.id == widget.activityID).isEmpty`
- `lib/vice_activity_history_page.dart:29` — `final Vice? vice = viceList.where((Vice item) => item.id == viceID).isEmpty`
