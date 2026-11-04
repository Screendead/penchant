# The calendar icon, date label and separator dot are literal white rather than an onSurface token

**Severity:** low

`vice_tracker.dart` colours three elements with `Colors.white` while its sibling `ViceChart` and `usage_graph_view.dart` consistently pull from the theme.

Contrast reads acceptably today only because the app hardcodes a single dark theme end to end; the value was never derived from or checked against the seeded `ColorScheme`.

## Evidence

- `lib/vice_tracker.dart:54` — `const Icon(Icons.calendar_month, color: Colors.white),`
- `lib/vice_tracker.dart:63` — `style: const TextStyle(color: Colors.white, fontSize: 16),`
- `lib/vice_tracker.dart:66` — `const CircleAvatar(backgroundColor: Colors.white, radius: 3),`
