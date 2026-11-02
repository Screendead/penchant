# The Not Found page's Go back button does nothing when it is the first route

**Severity:** low

`NotFound` offers a single button that calls `Navigator.pop`. On the web build an unrecognised deep link is generated as the initial route, leaving nothing beneath it on the stack, so the button is inert and there is no in-app way to reach the rest of the app.

`onUnknownRoute` is not set, so this page is also the sink for every mistyped route name.

## Evidence

- `lib/errors/not_found.dart:34` — `Navigator.of(context).pop();`
- `lib/errors/not_found.dart:36` — `child: const Text('Go back'),`
- `lib/main.dart:64` — `onGenerateRoute: (RouteSettings settings) {`
