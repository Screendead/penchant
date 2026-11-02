# Unused fields in the auth widgets and a commented-out chart parameter

**Severity:** low

`_AuthenticateState` declares an `options` list of the two auth pages and then builds an identical inline literal instead of reading it. `_SignInState` declares a `confirmPasswordController` that no widget references, left over from the shared shape with `Register`.

`vice_chart.dart` retains a commented-out `radarBackgroundColor` line that also references the deprecated `withOpacity` API, while the live code in the same file already uses `withValues`.

## Evidence

- `lib/authenticate.dart:13` — `final List<Widget> options = const <Widget>[SignIn(), Register()];`
- `lib/authenticate.dart:22` — `child: const [SignIn(), Register()][selectedIndex],`
- `lib/sign_in.dart:17` — `TextEditingController confirmPasswordController = TextEditingController();`
- `lib/vice_chart.dart:87` — `// radarBackgroundColor: Colors.pink.withOpacity(0.25),`
