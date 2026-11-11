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

  // Launch Services activates no LSUIElement app it launches, and from inside
  // `open -a` and `open -g` look the same (an oapp event, a default launch),
  // so only a login item's launch, which says so, stays in the background.
  // Read in did-finish, while that event is current.
  private var launchedAsLoginItem: Bool {
    NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?
      .enumCodeValue == keyAELaunchedAsLogInItem
  }

  // No super: FlutterAppDelegate does not implement this on macOS, so the call
  // raises "unrecognized selector", which AppKit swallows along with the rest
  // of the method.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if FlushMode.active {
      FlushMode.start()
    } else {
      FlushMode.clearOutcome()
      showMainWindow(activating: !launchedAsLoginItem)
      startMenuBarHelper()
    }
  }

  // The headless flush engine never answers a termination request. Otherwise
  // FlutterAppDelegate asks Dart first and the engine and Firebase then shut
  // down, which took seconds with the window still up: the windows go at once
  // and the process is given a second. Every write is in Firestore's local
  // queue and the device journal from the moment it is made, so a cut-short
  // shutdown loses none.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if FlushMode.active { return .terminateNow }
    for window in NSApp.windows { window.orderOut(nil) }
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { exit(0) }
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
    DispatchQueue.main.async { self.showMainWindow(activating: true) }
    startMenuBarHelper()
  }

  // The window is hidden at launch (MainMenu.xib), for flush mode, so every
  // other launch shows it.
  private func showMainWindow(activating: Bool) {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    if activating { activate() }
  }

  private func activate() {
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
      showMainWindow(activating: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
