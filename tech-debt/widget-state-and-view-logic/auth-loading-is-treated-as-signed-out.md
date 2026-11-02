# The app root shows the sign-in screen while auth state is still restoring

**Severity:** medium

`MyApp` reads the user provider's value and renders `Authenticate` whenever it is null. During the initial `AsyncLoading` of `authStateChanges`, before Firebase restores a persisted session, that value is null, so a signed-in user sees the sign-in screen on every cold start until the first auth event lands.

This is the same collapse of null and loading present in the leaf screens, occurring at the navigation root.

## Evidence

- `lib/main.dart:35` — `final User? user = ref.watch(userProvider).value;`
- `lib/main.dart:63` — `home: user == null ? const Authenticate() : const Homepage(),`
- `lib/providers/user_provider.dart:5` — `return FirebaseAuth.instance.authStateChanges();`
