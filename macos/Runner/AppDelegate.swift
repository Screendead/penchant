import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: StatusItemController?

  // applicationDidFinishLaunching never reached this class (macOS 27.2,
  // 2026-11-08; cause unknown), so the status item is made here. The main nib,
  // and with it the window and its engine, is loaded by now.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    guard statusItem == nil,
      let main = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      return
    }
    statusItem = StatusItemController(engine: main.engine) { [weak self] in
      self?.showMainWindow()
    }
  }

  // The status item logs with the window closed, so closing it keeps the app.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func showMainWindow() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
