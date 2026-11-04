# The same nullable id-lookup idiom is written out independently in two places

**Severity:** low

The pattern that tests a `where` clause for emptiness and otherwise calls `firstWhere` appears once in the editor page and once in the history page, both looking up the vice named by the route.

Each copy exists to make an id lookup nullable, and neither is factored into a shared helper. `vice_form.dart` makes the same lookup with `.where(...).firstOrNull`, so the codebase holds two spellings of one idea.

## Evidence

- `lib/vice_activity_editor_page.dart:176` — `viceList.where((Vice item) => item.id == widget.viceID).isEmpty`
- `lib/vice_activity_history_page.dart:84` — `final Vice? vice = viceList.where((Vice item) => item.id == viceID).isEmpty`
- `lib/vice_form.dart:183` — `final Vice? vice = viceList.where((Vice v) => v.id == viceID).firstOrNull;`
