# Mac widget logs wait for the app when the menu bar helper is not running

**Severity:** low

With Penchant closed, only the menu bar helper launches it to write what the widgets queue. If the user turns the
helper off in Login Items or kills it, widget logs wait for the app's next launch, and nothing in the widget says
so. The helper's own Quit hides its item and keeps the process running.

## Evidence (at `feat/mac-widget-sync-now`, 2026-11-08)

- `macos/PenchantMenuBar/PenchantMenuBarApp.swift:18` — `FlushLauncher.start()`
- `ios/PenchantWidgets/LogQueue.swift:162` — `static func requestFlush() {` (a Darwin notification, heard only by a running process)
