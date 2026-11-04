# An unused field in the auth widget and a commented-out chart parameter

**Severity:** low

`_AuthenticateState` declares an `options` list of the two auth pages and then builds an identical inline literal instead of reading it.

`vice_chart.dart` retains a commented-out `radarBackgroundColor` line that also references the deprecated `withOpacity` API, while the live code in the same file already uses `withValues`.

## Evidence

- `lib/authenticate.dart:13` — `final List<Widget> options = const <Widget>[SignIn(), Register()];`
- `lib/authenticate.dart:22` — `child: const [SignIn(), Register()][selectedIndex],`
- `lib/vice_chart.dart:87` — `// radarBackgroundColor: Colors.pink.withOpacity(0.25),`
