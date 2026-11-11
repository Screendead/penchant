import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  static let menuBarHelperID = "com.screendead.penchant.menubar"

  // A regular app, so Launch Services brings a launch the user made to the
  // front: since macOS 14 an app may not activate itself over the active app,
  // so an LSUIElement Penchant opened behind Safari. A flush-mode launch turns
  // accessory here, before NSApplicationMain registers the process with the
  // Dock; in applicationWillFinishLaunching its Dock icon had already flashed.
  // Flush mode stays accessory rather than prohibited, which may not be
  // activated, so the user's launch meanwhile can still bring it up.
  static func main() {
    if FlushMode.active {
      NSApplication.shared.setActivationPolicy(.accessory)
    }
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
  }

  // No super: FlutterAppDelegate does not implement this on macOS, so the call
  // raises "unrecognized selector", which AppKit swallows along with the rest
  // of the method. Activation is Launch Services' call: `open -g` and a login
  // launch stay behind.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if FlushMode.active {
      FlushMode.start()
    } else {
      FlushMode.clearOutcome()
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      startMenuBarHelper()
    }
  }

  private var quitAsked = false

  // The headless flush engine never answers a termination request. Otherwise
  // the windows go at once, and FlutterAppDelegate asks Dart, which answers
  // when the server has acknowledged every write or after 3 seconds
  // (lib/writes/quit_when_synced.dart); AppKit then asks here a second time.
  // The engine's and Firebase's own shutdown took seconds, so the process
  // exits half a second after that second ask, or 4.5 seconds after the first
  // if Dart never answers. A write unsent by then is in Firestore's queue on
  // disk and goes on the next launch.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if FlushMode.active { return .terminateNow }
    for window in NSApp.windows { window.orderOut(nil) }
    DispatchQueue.global().asyncAfter(deadline: .now() + (quitAsked ? 0.5 : 4.5)) { exit(0) }
    quitAsked = true
    return super.applicationShouldTerminate(sender)
  }

  // The user opened Penchant while it ran to flush: it becomes the normal app.
  // An accessory app turned regular mid-session can keep the previous app's
  // menus in the menu bar until it is activated again, so the window and the
  // activation wait for the policy change to take, a runloop turn later.
  private func leaveFlushMode() {
    FlushMode.leave()
    NSApp.setActivationPolicy(.regular)
    (mainFlutterWindow as? MainFlutterWindow)?.attachFlutter()
    DispatchQueue.main.async { self.showMainWindow() }
    startMenuBarHelper()
  }

  // The window is hidden at launch (MainMenu.xib), for flush mode.
  private func showMainWindow() {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
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
    // Registering launches it, before it shows up as running, so opening it
    // as well would start a second copy, and two helpers would both launch
    // Penchant to flush.
    if service.status != .enabled {
      do {
        try service.register()
        return
      } catch {
        NSLog("Penchant: menu bar helper not registered: \(error)")
      }
    }
    // A running helper whose item the user hid brings it back.
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(showMenuBarNotification as CFString), nil, nil,
      true)
    // An item enabled earlier and quit since does not relaunch until the next
    // login, so the app opens it. A helper left over from an older build
    // exits on that notification (Staleness, PenchantMenuBarApp.swift), so
    // the check runs again once it has had time to go.
    openMenuBarHelperIfMissing()
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.openMenuBarHelperIfMissing() }
  }

  private func openMenuBarHelperIfMissing() {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.menuBarHelperID).isEmpty else {
      return
    }
    let helper = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Library/LoginItems/PenchantMenuBar.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
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
      showMainWindow()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
