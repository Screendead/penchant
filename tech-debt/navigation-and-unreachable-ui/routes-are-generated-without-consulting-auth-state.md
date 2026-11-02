# onGenerateRoute never reads userProvider, so pushed routes outlive the session

**Severity:** medium

The root swaps `home` between `Authenticate` and `Homepage`, but any route already pushed above it stays on the stack when the session ends. Its providers then return empty streams, so the route becomes an indefinite spinner floating over the sign-in screen.

## Evidence

- `lib/main.dart:64` — `onGenerateRoute: (RouteSettings settings) {`
- `lib/main.dart:64-109` — the closure body (checked with `grep -n "ref\.\|user" lib/main.dart`) never references `ref` or `user`; both only appear at lines 35 and 63, outside `onGenerateRoute`
- `lib/main.dart:35` — `final User? user = ref.watch(userProvider).value;`
