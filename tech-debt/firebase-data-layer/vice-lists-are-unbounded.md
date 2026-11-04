# The vice lists are the last list queries with no limit

**Severity:** low

Every activity query is bounded by a date window, a page size, a single document or a server-side count, but `viceListProvider` and `unarchivedViceListProvider` still stream all of a user's vices, archived ones included in the first. Nothing caps how many vices a user can create. Vices are created by hand, so the set is small in practice, and the number of vices no longer limits any query since the day query dropped its `in` filter. A `limit` on its own would hide a user's oldest vices from every screen without saying so; whether to cap the count (with a guard in Add Vice and the rules) or to leave it unbounded is a product call that has not been made.

## Evidence

- `lib/providers/vice_list_provider.dart:9` — `.collection('vices')` through `.orderBy('createdAt', descending: true)` at line 11, no `.limit(`
- `lib/providers/unarchived_vice_list_provider.dart:9` — the same, with the `archived` filter, no `.limit(`
