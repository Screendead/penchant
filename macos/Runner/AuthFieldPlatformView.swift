import Cocoa
import FlutterMacOS

// Native Email and Password fields for the sign-in form. Flutter's macOS text
// input gives AutoFill nothing to work with (see CLAUDE.md), while a real
// NSTextField / NSSecureTextField with a content type gets the Passwords
// prompt. Each view talks to Dart over its own channel,
// "penchant/auth_field/<view id>".
class AuthFieldFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "penchant/auth_field"

  private let messenger: FlutterBinaryMessenger
  private weak var flutterView: NSView?

  init(messenger: FlutterBinaryMessenger, flutterView: NSView) {
    self.messenger = messenger
    self.flutterView = flutterView
  }

  static func register(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "AuthField")
    registrar.register(
      AuthFieldFactory(messenger: registrar.messenger, flutterView: controller.view),
      withId: viewType)
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let channel = FlutterMethodChannel(
      name: "\(AuthFieldFactory.viewType)/\(viewId)", binaryMessenger: messenger)
    return AuthFieldView(
      channel: channel, flutterView: flutterView, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private protocol AuthFieldOwner: AnyObject {
  func fieldDidBecomeFirstResponder()
  func fieldValueMayHaveChanged()
}

// Reports focus, which NSControl's delegate only learns of at the first edit,
// and programmatic value changes, which reach no delegate at all.
private class PlainAuthTextField: NSTextField {
  weak var owner: AuthFieldOwner?
  override var stringValue: String { didSet { owner?.fieldValueMayHaveChanged() } }
  override var objectValue: Any? { didSet { owner?.fieldValueMayHaveChanged() } }
  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { owner?.fieldDidBecomeFirstResponder() }
    return became
  }
}

private class SecureAuthTextField: NSSecureTextField {
  weak var owner: AuthFieldOwner?
  override var stringValue: String { didSet { owner?.fieldValueMayHaveChanged() } }
  override var objectValue: Any? { didSet { owner?.fieldValueMayHaveChanged() } }
  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { owner?.fieldDidBecomeFirstResponder() }
    return became
  }
}

class AuthFieldView: NSView, NSTextFieldDelegate, AuthFieldOwner {
  private let channel: FlutterMethodChannel
  private weak var flutterView: NSView?
  private var field: NSTextField!
  private var kind: String
  private var obscured: Bool
  private var placeholder = ""
  private var textColor = NSColor.labelColor
  private var placeholderColor = NSColor.placeholderTextColor
  private var caretColor = NSColor.labelColor
  private var lastSent = ""
  private var focused = false
  private var poll: Timer?
  private var reading = false

  init(channel: FlutterMethodChannel, flutterView: NSView?, arguments: [String: Any]) {
    self.channel = channel
    self.flutterView = flutterView
    kind = arguments["kind"] as? String ?? "email"
    obscured = kind != "email"
    super.init(frame: .zero)
    apply(arguments)
    lastSent = arguments["text"] as? String ?? ""
    installField(text: lastSent)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  deinit {
    poll?.invalidate()
    channel.setMethodCallHandler(nil)
  }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let height = ceil(field.intrinsicContentSize.height)
    field.frame = NSRect(
      x: 0, y: max(0, (bounds.height - height) / 2), width: bounds.width, height: height)
  }

  // AutoFill may write the value by a route that tells no delegate, so the
  // value is also polled while the view is on screen.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    poll?.invalidate()
    poll = nil
    if window != nil {
      poll = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
        self?.fieldValueMayHaveChanged()
      }
    }
  }

  private func apply(_ arguments: [String: Any]) {
    if let value = arguments["placeholder"] as? String { placeholder = value }
    if let value = arguments["textColor"] as? Int { textColor = color(value) }
    if let value = arguments["placeholderColor"] as? Int { placeholderColor = color(value) }
    if let value = arguments["caretColor"] as? Int { caretColor = color(value) }
  }

  private func color(_ argb: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }

  private var contentType: NSTextContentType {
    switch kind {
    case "email": return .username
    case "newPassword":
      if #available(macOS 14.0, *) { return .newPassword }
      return .password
    default: return .password
    }
  }

  private func installField(text: String) {
    let hadFocus = focused
    field?.delegate = nil
    field?.removeFromSuperview()
    let next: NSTextField
    if obscured {
      let secure = SecureAuthTextField()
      next = secure
      secure.stringValue = text
      secure.owner = self
    } else {
      let plain = PlainAuthTextField()
      next = plain
      plain.stringValue = text
      plain.owner = self
    }
    next.contentType = contentType
    next.isBordered = false
    next.isBezeled = false
    next.drawsBackground = false
    next.focusRingType = .none
    next.usesSingleLineMode = true
    next.cell?.wraps = false
    next.cell?.isScrollable = true
    next.lineBreakMode = .byClipping
    next.font = NSFont.systemFont(ofSize: 15.5, weight: .medium)
    next.delegate = self
    field = next
    addSubview(next)
    restyle()
    needsLayout = true
    if hadFocus { window?.makeFirstResponder(next) }
  }

  private func restyle() {
    field.textColor = textColor
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .foregroundColor: placeholderColor, .font: field.font ?? NSFont.systemFont(ofSize: 15.5),
      ])
    field.setAccessibilityLabel(placeholder)
    (field.currentEditor() as? NSTextView)?.insertionPointColor = caretColor
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setText":
      let text = arguments["text"] as? String ?? ""
      lastSent = text
      if field.stringValue != text { field.stringValue = text }
    case "configure":
      apply(arguments)
      if let value = arguments["kind"] as? String, value != kind {
        kind = value
        field.contentType = contentType
      }
      restyle()
    case "setObscured":
      let value = arguments["obscured"] as? Bool ?? true
      if value != obscured {
        obscured = value
        installField(text: field.stringValue)
      }
    case "focus":
      if field.currentEditor() == nil { window?.makeFirstResponder(field) }
    case "blur":
      if field.currentEditor() != nil, let flutterView = flutterView {
        window?.makeFirstResponder(flutterView)
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  fileprivate func fieldDidBecomeFirstResponder() {
    focused = true
    (field.currentEditor() as? NSTextView)?.insertionPointColor = caretColor
    channel.invokeMethod("focusChanged", arguments: ["focused": true])
  }

  fileprivate func fieldValueMayHaveChanged() {
    // Reading stringValue mid-edit commits the editor's text, which may come
    // back through the overridden setters.
    guard let field = field, !reading else { return }
    reading = true
    let text = field.stringValue
    reading = false
    if text != lastSent {
      lastSent = text
      channel.invokeMethod("changed", arguments: ["text": text])
    }
  }

  func controlTextDidChange(_ notification: Notification) {
    fieldValueMayHaveChanged()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    fieldValueMayHaveChanged()
    focused = false
    channel.invokeMethod("focusChanged", arguments: ["focused": false])
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.insertTab(_:)):
      channel.invokeMethod("tab", arguments: ["forward": true])
    case #selector(NSResponder.insertBacktab(_:)):
      channel.invokeMethod("tab", arguments: ["forward": false])
    case #selector(NSResponder.insertNewline(_:)):
      fieldValueMayHaveChanged()
      channel.invokeMethod("submitted", arguments: ["text": field.stringValue])
    default:
      return false
    }
    return true
  }
}
