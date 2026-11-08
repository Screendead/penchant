import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  static let menuBarHelperID = "com.screendead.penchant.menubar"

  // applicationDidFinishLaunching never reached this class (macOS 27.2,
  // 2026-11-08; cause unknown), so launch work runs here.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    startMenuBarHelper()
  }

  // The menu bar helper (macos/PenchantMenuBar) is a login item, so it starts
  // at login and stays when the app quits. `-unregisterMenuBarHelper` removes
  // it and quits, for a test copy that must not leave its registration behind.
  private func startMenuBarHelper() {
    guard #available(macOS 13.0, *) else { return }
    let service = SMAppService.loginItem(identifier: Self.menuBarHelperID)
    if CommandLine.arguments.contains("-unregisterMenuBarHelper") {
      try? service.unregister()
      NSApp.terminate(nil)
      return
    }
    if service.status != .enabled {
      do {
        try service.register()
      } catch {
        NSLog("Penchant: menu bar helper not registered: \(error)")
      }
    }
    // Registering launches it; an item enabled earlier and quit since does not
    // relaunch until the next login, so the app opens it.
    if NSRunningApplication.runningApplications(withBundleIdentifier: Self.menuBarHelperID).isEmpty {
      let helper = Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Library/LoginItems/PenchantMenuBar.app")
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      configuration.addsToRecentItems = false
      NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
    }
  }

  // Closing the window keeps the app, so it goes on flushing what the widgets
  // and the menu bar queue.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
