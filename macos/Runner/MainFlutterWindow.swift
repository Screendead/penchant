import Cocoa
import FlutterMacOS
import LocalAuthentication

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
    DeviceAuth.register(with: flutterViewController.registrar(forPlugin: "DeviceAuth").messenger)
    EntryPrompt.register(with: flutterViewController.registrar(forPlugin: "EntryPrompt"))
    CalendarChannel.register(with: flutterViewController.registrar(forPlugin: "CalendarChannel"))
    super.awakeFromNib()
  }
}

// The Dart side is lib/journal_key/secret_clipboard.dart. macOS has no
// local-only pasteboard item, so Universal Clipboard still carries the copy
// to the user's other devices. The nspasteboard.org markers ask clipboard
// managers to skip it, and it is cleared after the delay unless something
// else has been copied since.
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

// The Dart side is lib/app_lock/device_auth.dart. The device-owner policy
// falls back to the passcode when biometrics fail or are not set up.
enum DeviceAuth {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.screendead.penchant/device_auth", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "status":
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        // biometryType is set only once canEvaluatePolicy has run.
        result(["available": available, "biometry": biometryName(context.biometryType)])
      case "authenticate":
        guard let args = call.arguments as? [String: Any], let reason = args["reason"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
          success, error in
          let outcome = success ? "success" : outcomeName(error)
          DispatchQueue.main.async { result(outcome) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func biometryName(_ type: LABiometryType) -> String {
    switch type {
    case .faceID: return "faceID"
    case .touchID: return "touchID"
    default: return "none"
    }
  }

  static func outcomeName(_ error: Error?) -> String {
    switch (error as? LAError)?.code {
    case .userCancel?, .systemCancel?, .appCancel?, .userFallback?, .notInteractive?:
      return "cancelled"
    case .passcodeNotSet?:
      return "unavailable"
    default:
      return "failed"
    }
  }
}
