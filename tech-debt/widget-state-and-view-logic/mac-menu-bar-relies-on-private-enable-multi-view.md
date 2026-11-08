# The Mac menu bar popover relies on a private Flutter engine method

**Severity:** medium

The popover hosts a second Flutter view on the main window's engine, which needs a multi-view engine. The macOS
embedder's public header has no way to ask for one, so `MainFlutterWindow` calls `enableMultiView` by selector before
the engine runs, guarded by a `precondition`. If a Flutter upgrade renames or removes that method, the Mac app stops
at launch instead of running without the popover. Each Flutter pin bump needs a launch of the Mac app to catch it.

## Evidence (at `master`, 2026-11-08)

- `macos/Runner/MainFlutterWindow.swift:25` — `let enableMultiView = NSSelectorFromString("enableMultiView")`
- `macos/Runner/MainFlutterWindow.swift:26` — `precondition(engine.responds(to: enableMultiView), "FlutterEngine lost enableMultiView")`
