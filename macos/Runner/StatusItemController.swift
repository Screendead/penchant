import Cocoa
import FlutterMacOS

// The menu bar's status item. Its popover hosts a second Flutter view on the
// main window's engine (lib/menu_bar/menu_bar_popover.dart), made when the
// popover opens and released when it closes, so the Dart side mounts the
// popover's widgets only while it shows.
class StatusItemController: NSObject, NSPopoverDelegate {
  static let channelName = "penchant/menu_bar"
  static let popoverSize = NSSize(width: 340, height: 580)

  private let engine: FlutterEngine
  private let openMainWindow: () -> Void
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let popover = NSPopover()
  private let channel: FlutterMethodChannel
  // A transient popover closes on the mouse-down outside it, which includes
  // the status button, so the button's action that follows would reopen it.
  private static let reopenGuard: TimeInterval = 0.3
  private var closedAt: Date?

  init(engine: FlutterEngine, openMainWindow: @escaping () -> Void) {
    self.engine = engine
    self.openMainWindow = openMainWindow
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: engine.binaryMessenger)
    super.init()

    popover.behavior = .transient
    popover.contentSize = Self.popoverSize
    popover.delegate = self

    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "circle.dashed.inset.filled", accessibilityDescription: "Penchant")
      if button.image == nil {
        button.title = "P"
      }
      button.target = self
      button.action = #selector(toggle(_:))
    }

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "openMainWindow":
        self?.popover.performClose(nil)
        self?.openMainWindow()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @objc private func toggle(_ sender: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(sender)
      return
    }
    if let closedAt, Date().timeIntervalSince(closedAt) < Self.reopenGuard {
      return
    }
    let view = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    view.view.frame = NSRect(origin: .zero, size: Self.popoverSize)
    popover.contentViewController = view
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
    popover.contentViewController?.view.window?.makeKey()
  }

  func popoverDidClose(_ notification: Notification) {
    closedAt = Date()
    // Releasing the controller removes its view from the engine.
    popover.contentViewController = nil
  }
}
