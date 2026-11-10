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

  // In flush mode the window stays hidden and empty, so no second engine runs
  // the app's main() beside the headless flush; becoming a normal app
  // attaches Flutter then (AppDelegate.leaveFlushMode).
  override func awakeFromNib() {
    if !FlushMode.active {
      attachFlutter()
    }
    super.awakeFromNib()
  }

  func attachFlutter() {
    guard !(contentViewController is FlutterViewController) else { return }
    let flutterViewController = FlutterViewController()
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
    SecretPasteboard.register(with: flutterViewController.registrar(forPlugin: "SecretPasteboard").messenger)
  }
}

// The Dart side is lib/journal_key/secret_clipboard.dart. macOS has no
// local-only pasteboard item; the nspasteboard.org markers ask clipboard
// managers and Universal Clipboard to skip it, and it is cleared after the
// delay unless something else has been copied since.
enum SecretPasteboard {
  static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
  static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.screendead.penchant/secret_clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "copy", let args = call.arguments as? [String: Any],
        let text = args["text"] as? String, let seconds = args["seconds"] as? Int
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.declareTypes([.string, concealed, transient], owner: nil)
      pasteboard.setString(text, forType: .string)
      pasteboard.setData(Data(), forType: concealed)
      pasteboard.setData(Data(), forType: transient)
      let written = pasteboard.changeCount
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
        if pasteboard.changeCount == written {
          pasteboard.clearContents()
        }
      }
      result(nil)
    }
  }
}
