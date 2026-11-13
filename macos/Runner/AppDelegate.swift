import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  static let menuBarHelperID = "com.screendead.penchant.menubar"

  // No super: FlutterAppDelegate does not implement this on macOS, so the call
  // raises "unrecognized selector", which AppKit swallows along with the rest
  // of the method. The app never activates itself: Launch Services activates
  // a regular app's launch the user made and leaves `open -g` in the
  // background.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    SyncApp.clearOutcome()
    SyncApp.flushOnceEnded()
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    startMenuBarHelper()
  }

  private var quitAsked = false

  // The windows go at once, and FlutterAppDelegate asks Dart, which answers
  // when the server has acknowledged every write or after 3 seconds
  // (lib/writes/quit_when_synced.dart); AppKit then asks here a second time.
  // The engine's and Firebase's own shutdown took seconds, so the process
  // exits half a second after that second ask, or 4.5 seconds after the first
  // if Dart never answers. A write unsent by then is in Firestore's queue on
  // disk and goes on the next launch.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    for window in NSApp.windows { window.orderOut(nil) }
    DispatchQueue.global().asyncAfter(deadline: .now() + (quitAsked ? 0.5 : 4.5)) { exit(0) }
    quitAsked = true
    return super.applicationShouldTerminate(sender)
  }

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
    // A running helper whose item the user hid brings it back; one from
    // another build or another copy of Penchant exits (Staleness).
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(showMenuBarNotification as CFString), nil, nil,
      true)
    // Registering launches it, before it shows up as running, so opening it
    // as well would start a second copy, and two helpers would both launch
    // PenchantSync to flush.
    if service.status != .enabled {
      do {
        try service.register()
        return
      } catch {
        NSLog("Penchant: menu bar helper not registered: \(error)")
      }
    }
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
    if !flag {
      showMainWindow()
    }
    return true
  }

  // A widget's or the menu bar's "What was going on?" (EntryLink). It is not
  // a reopen, so a flush-mode run becomes the normal app here. After this
  // turn of the run loop: at launch it can come before
  // applicationDidFinishLaunching.
  override func application(_ application: NSApplication, open urls: [URL]) {
    let others = urls.filter { !EntryPrompt.open($0) }
    if others.count < urls.count {
      DispatchQueue.main.async {
        self.showMainWindow()
      }
    }
    if !others.isEmpty,
      FlutterAppDelegate.instancesRespond(to: #selector(NSApplicationDelegate.application(_:open:)))
    {
      super.application(application, open: others)
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
