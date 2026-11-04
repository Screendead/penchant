# The editor page spells the nullable id-lookup differently from the rest

**Severity:** low

The editor page tests a `where` clause for emptiness and otherwise calls `firstWhere`; the history page and `vice_form.dart` use `.where(...).firstOrNull`.

## Evidence

- `lib/vice_activity_editor_page.dart:204` — `viceList.where((Vice item) => item.id == widget.viceID).isEmpty`
