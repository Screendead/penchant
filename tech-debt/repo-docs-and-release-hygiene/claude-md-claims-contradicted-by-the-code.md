# CLAUDE.md's provider chain is wrong about which vice list the activity providers watch

**Severity:** medium

Its provider chain groups `unarchivedViceListProvider` with `viceListProvider` as feeding the day and list providers, when only the latter is watched by them and the former is a leaf read by two widgets.

## Evidence

- `CLAUDE.md`, "Provider chain" — `` `userProvider` (auth state) → `viceListProvider` / `unarchivedViceListProvider` → the day and list activity providers ``
- `lib/providers/vice_activity_day_provider.dart:13` and `lib/providers/vice_activity_list_provider.dart:11` watch `viceListProvider` only; `unarchivedViceListProvider` is watched by `lib/vice_chart.dart` and `lib/widgets/record_new_activity_dialog.dart`.
