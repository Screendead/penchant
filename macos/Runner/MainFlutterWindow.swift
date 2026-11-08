import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Wider than the 900 pt where the split view starts, so a new window shows it.
  static let defaultContentSize = NSSize(width: 1200, height: 780)
  // Narrow enough that resizing still reaches the phone layout.
  static let minimumContentSize = NSSize(width: 390, height: 600)
  static let frameAutosaveName = "MainWindow"

  // The default size, shrunk to fit a smaller screen but never below the minimum.
  static func initialContentSize(fitting available: NSSize) -> NSSize {
    NSSize(
      width: max(min(defaultContentSize.width, available.width), minimumContentSize.width),
      height: max(min(defaultContentSize.height, available.height), minimumContentSize.height))
  }

  override func awakeFromNib() {
    // The status item's popover is a second view on this engine
    // (StatusItemController), and an engine takes a second view controller
    // only with multi-view enabled before its first. enableMultiView is not in
    // the public header (Flutter 3.44); without it the popover's controller
    // init raises and AppKit swallows the exception, so a click does nothing.
    let engine = FlutterEngine(name: "penchant", project: nil)
    let enableMultiView = NSSelectorFromString("enableMultiView")
    precondition(engine.responds(to: enableMultiView), "FlutterEngine lost enableMultiView")
    engine.perform(enableMultiView)
    // Run first: a view added to a running engine is announced to Dart.
    engine.run(withEntrypoint: nil)
    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    self.contentViewController = flutterViewController

    self.contentMinSize = Self.minimumContentSize
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      self.setContentSize(
        Self.initialContentSize(fitting: self.contentRect(forFrameRect: visible).size))
    } else {
      self.setContentSize(Self.defaultContentSize)
    }
    self.center()
    // A frame saved by an earlier launch wins over the default.
    self.setFrameUsingName(Self.frameAutosaveName)
    self.setFrameAutosaveName(Self.frameAutosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AuthFieldsFactory.register(with: flutterViewController)
    QueueListener.start(WidgetBridge.register(with: flutterViewController.registrar(forPlugin: "WidgetBridge")))

    super.awakeFromNib()
  }
}
