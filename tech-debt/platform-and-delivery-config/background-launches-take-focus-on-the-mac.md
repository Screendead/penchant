# A Mac launch nobody asked to bring forward still takes focus

**Severity:** low

The app is an `LSUIElement` (so a flush-mode launch shows no Dock icon), and Launch Services activates no such app,
so every normal launch shows its window and activates it itself. From inside, `open -g` and `open -a` look the
same: an `oapp` event with no `keyAEPropData` and `NSApplicationLaunchIsDefaultLaunchKey` set, measured on this Mac.
Only a login-item launch is told apart. A background launch therefore takes focus. That includes `open -g`, most
likely the system's launch to run `LogOneIntent` for Shortcuts or Siri, and a login-session restore, none of which
has been tested.

## Evidence (at `feat/mac-widget-sync-now`, 2026-11-08)

- `macos/Runner/AppDelegate.swift:28` — `.enumCodeValue == keyAELaunchedAsLogInItem`
- `macos/Runner/AppDelegate.swift:39` — `showMainWindow(activating: !launchedAsLoginItem)`
