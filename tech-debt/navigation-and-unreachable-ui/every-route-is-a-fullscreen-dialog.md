# All three MaterialPageRoute construction sites set fullscreenDialog

**Severity:** low

`onGenerateRoute` has only three `MaterialPageRoute<void>` construction sites, but each sets `fullscreenDialog: true`, so every one of the named destinations behind them — Settings, Account Settings, Manage Data, Add Vice, the vice activity history/editor pages, and the Not Found page — is pushed as a fullscreen dialog. Every navigation in the app is therefore a modal bottom-up transition presenting a close icon rather than a back arrow, regardless of whether the destination is modal in nature, and the error page inherits the same presentation as the deliberate modals.

## Evidence

- `lib/main.dart:64` — `onGenerateRoute: (RouteSettings settings) {`
- `lib/main.dart:71` — `fullscreenDialog: true,`
- `lib/main.dart:82` — `fullscreenDialog: true,`
- `lib/main.dart:93` — `fullscreenDialog: true,`
