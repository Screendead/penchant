# The day-picker header builds Today, Yesterday and N days ago from a nested ternary

**Severity:** low

`vice_tracker.dart` composes its own three-way relative-date string from a nested ternary rather than using any locale-aware relative-time formatting.

The days-ago branch hardcodes a single English plural form, with no provision for other languages' word order or plural categories.

## Evidence

- `lib/vice_tracker.dart:57` — `daysAgo == 0\n                        ? 'Today'\n                        : daysAgo == 1\n                            ? 'Yesterday'\n                            : '$daysAgo days ago',`
