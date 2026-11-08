import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  static let menuBarHelperID = "com.screendead.penchant.menubar"

  // FlutterAppDelegate implements this one (it names the window and menus).
  // Info.plist's LSUIElement and the nib's window hidden at launch
  // (MainMenu.xib) keep a flush-mode launch out of the Dock and off screen: a
  // regular app's Dock icon is up before this runs. Flush mode stays an
  // accessory app rather than a prohibited one, which may not be activated,
  // so the user's launch meanwhile can still bring it up.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    if !FlushMode.active {
      NSApp.setActivationPolicy(.regular)
    }
  }

  // No super: FlutterAppDelegate does not implement this on macOS, so the call
  // raises "unrecognized selector", which AppKit swallows along with the rest
  // of the method.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if FlushMode.active {
      FlushMode.start()
    } else {
      showMainWindow()
      startMenuBarHelper()
    }
  }

  // The headless flush engine never answers a termination request.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    FlushMode.active ? .terminateNow : super.applicationShouldTerminate(sender)
  }

  // The user opened Penchant while it ran to flush: it becomes the normal app.
  private func leaveFlushMode() {
    FlushMode.leave()
    NSApp.setActivationPolicy(.regular)
    (mainFlutterWindow as? MainFlutterWindow)?.attachFlutter()
    showMainWindow()
    startMenuBarHelper()
  }

  // Launch Services does not activate an LSUIElement app it launches, and
  // window restoration after a flush-mode run would leave the window hidden.
  private func showMainWindow() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
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
    if FlushMode.active {
      leaveFlushMode()
      return true
    }
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
