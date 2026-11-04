# An unused field in the auth widget

**Severity:** low

`_AuthenticateState` declares an `options` list of the two auth pages and then builds an identical inline literal instead of reading it.

## Evidence

- `lib/authenticate.dart:13` — `final List<Widget> options = const <Widget>[SignIn(), Register()];`
- `lib/authenticate.dart:22` — `child: const [SignIn(), Register()][selectedIndex],`
