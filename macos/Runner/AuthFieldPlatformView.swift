import Cocoa
import FlutterMacOS

// Native Email and Password fields for the sign-in form. Flutter's macOS text
// input gives AutoFill nothing to work with (see CLAUDE.md), while a real
// NSTextField / NSSecureTextField with a content type gets the Passwords
// prompt. Both fields are siblings in one view, as in a plain AppKit form:
// as separate platform views, a fill started from Email left Password empty.
// The view talks to Dart over "penchant/auth_fields/<view id>"; every message
// names its field, "email" or "password".
class AuthFieldsFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "penchant/auth_fields"

  private let messenger: FlutterBinaryMessenger
  private weak var flutterView: NSView?

  init(messenger: FlutterBinaryMessenger, flutterView: NSView) {
    self.messenger = messenger
    self.flutterView = flutterView
  }

  static func register(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "AuthFields")
    registrar.register(
      AuthFieldsFactory(messenger: registrar.messenger, flutterView: controller.view),
      withId: viewType)
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let channel = FlutterMethodChannel(
      name: "\(AuthFieldsFactory.viewType)/\(viewId)", binaryMessenger: messenger)
    return AuthFieldsView(
      channel: channel, flutterView: flutterView, arguments: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private protocol AuthFieldOwner: AnyObject {
  func fieldDidBecomeFirstResponder(_ field: NSTextField)
  func fieldValueMayHaveChanged()
}

// Reports focus, which NSControl's delegate only learns of at the first edit,
// and programmatic value changes (AutoFill filling the other field), which
// reach no delegate at all.
private class PlainAuthTextField: NSTextField {
  weak var owner: AuthFieldOwner?
  override var stringValue: String { didSet { owner?.fieldValueMayHaveChanged() } }
  override var objectValue: Any? { didSet { owner?.fieldValueMayHaveChanged() } }
  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { owner?.fieldDidBecomeFirstResponder(self) }
    return became
  }
}

private class SecureAuthTextField: NSSecureTextField {
  weak var owner: AuthFieldOwner?
  override var stringValue: String { didSet { owner?.fieldValueMayHaveChanged() } }
  override var objectValue: Any? { didSet { owner?.fieldValueMayHaveChanged() } }
  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { owner?.fieldDidBecomeFirstResponder(self) }
    return became
  }
}

private final class Slot {
  let name: String
  var kind: String
  var obscured: Bool
  var placeholder = ""
  var frame = NSRect.zero
  var lastSent: String
  var focused = false
  var field: NSTextField!

  init(name: String, arguments: [String: Any]) {
    self.name = name
    kind = arguments["kind"] as? String ?? name
    obscured = arguments["obscured"] as? Bool ?? (name != "email")
    lastSent = arguments["text"] as? String ?? ""
  }

  var contentType: NSTextContentType {
    switch kind {
    case "email": return .username
    case "newPassword":
      if #available(macOS 14.0, *) { return .newPassword }
      return .password
    default: return .password
    }
  }

  // The field editor's text while editing, so reading never commits the
  // edit (NSControl.stringValue would, mid-AutoFill).
  var currentText: String {
    (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
  }
}

class AuthFieldsView: NSView, NSTextFieldDelegate, AuthFieldOwner {
  private let channel: FlutterMethodChannel
  private weak var flutterView: NSView?
  private let email: Slot
  private let password: Slot
  private var textColor = NSColor.labelColor
  private var placeholderColor = NSColor.placeholderTextColor
  private var caretColor = NSColor.labelColor
  private var flushQueued = false
  private var poll: Timer?

  init(channel: FlutterMethodChannel, flutterView: NSView?, arguments: [String: Any]) {
    self.channel = channel
    self.flutterView = flutterView
    email = Slot(name: "email", arguments: arguments["email"] as? [String: Any] ?? [:])
    password = Slot(name: "password", arguments: arguments["password"] as? [String: Any] ?? [:])
    super.init(frame: .zero)
    for slot in [email, password] {
      let config = arguments[slot.name] as? [String: Any] ?? [:]
      apply(config, to: slot)
      installField(in: slot, text: slot.lastSent)
    }
    applyLayout(arguments["layout"] as? [String: Any] ?? [:])
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
    for slot in [email, password] {
      let height = ceil(slot.field.intrinsicContentSize.height)
      slot.field.frame = NSRect(
        x: slot.frame.minX, y: slot.frame.minY + max(0, (slot.frame.height - height) / 2),
        width: slot.frame.width, height: height)
    }
  }

  // A safety net in case AutoFill writes a value by a route no override
  // sees. It reads without committing an edit, so it cannot disturb a fill.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    poll?.invalidate()
    poll = nil
    if window != nil {
      poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        self?.fieldValueMayHaveChanged()
      }
    }
  }

  private func slot(named name: Any?) -> Slot? {
    switch name as? String {
    case "email": return email
    case "password": return password
    default: return nil
    }
  }

  private func slot(for field: NSControl) -> Slot? {
    if field === email.field { return email }
    if field === password.field { return password }
    return nil
  }

  private func apply(_ arguments: [String: Any], to slot: Slot) {
    if let value = arguments["placeholder"] as? String { slot.placeholder = value }
    if let value = arguments["textColor"] as? Int { textColor = color(value) }
    if let value = arguments["placeholderColor"] as? Int { placeholderColor = color(value) }
    if let value = arguments["caretColor"] as? Int { caretColor = color(value) }
  }

  private func applyLayout(_ arguments: [String: Any]) {
    for slot in [email, password] {
      if let rect = arguments[slot.name] as? [Double], rect.count == 4 {
        slot.frame = NSRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
      }
    }
    needsLayout = true
  }

  private func color(_ argb: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }

  private func installField(in slot: Slot, text: String) {
    let hadFocus = slot.focused
    slot.field?.delegate = nil
    slot.field?.removeFromSuperview()
    let next: NSTextField
    if slot.obscured {
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
    next.contentType = slot.contentType
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
    slot.field = next
    addSubview(next)
    if let emailField = email.field, let passwordField = password.field {
      emailField.nextKeyView = passwordField
    }
    restyle(slot)
    needsLayout = true
    if hadFocus { window?.makeFirstResponder(next) }
  }

  private func restyle(_ slot: Slot) {
    let field = slot.field!
    field.textColor = textColor
    field.placeholderAttributedString = NSAttributedString(
      string: slot.placeholder,
      attributes: [
        .foregroundColor: placeholderColor, .font: field.font ?? NSFont.systemFont(ofSize: 15.5),
      ])
    field.setAccessibilityLabel(slot.placeholder)
    (field.currentEditor() as? NSTextView)?.insertionPointColor = caretColor
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    if call.method == "layout" {
      applyLayout(arguments)
      result(nil)
      return
    }
    guard let slot = slot(named: arguments["field"]) else {
      result(FlutterMethodNotImplemented)
      return
    }
    switch call.method {
    case "setText":
      let text = arguments["text"] as? String ?? ""
      slot.lastSent = text
      if slot.currentText != text { slot.field.stringValue = text }
    case "configure":
      apply(arguments, to: slot)
      if let value = arguments["kind"] as? String, value != slot.kind {
        slot.kind = value
        slot.field.contentType = slot.contentType
      }
      restyle(email)
      restyle(password)
    case "setObscured":
      let value = arguments["obscured"] as? Bool ?? true
      if value != slot.obscured {
        slot.obscured = value
        installField(in: slot, text: slot.currentText)
      }
    case "focus":
      // Already editing: a second makeFirstResponder would restart the
      // field editor, and with it any AutoFill prompt.
      if slot.field.currentEditor() == nil { window?.makeFirstResponder(slot.field) }
    case "blur":
      if slot.field.currentEditor() != nil, let flutterView = flutterView {
        window?.makeFirstResponder(flutterView)
      }
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(nil)
  }

  fileprivate func fieldDidBecomeFirstResponder(_ field: NSTextField) {
    guard let slot = slot(for: field) else { return }
    (field.currentEditor() as? NSTextView)?.insertionPointColor = caretColor
    if slot.focused { return }
    slot.focused = true
    channel.invokeMethod("focusChanged", arguments: ["field": slot.name, "focused": true])
  }

  // A fill sets both fields in one pass; this sends whatever changed in one
  // message once that pass is over.
  fileprivate func fieldValueMayHaveChanged() {
    guard !flushQueued else { return }
    flushQueued = true
    DispatchQueue.main.async { [weak self] in self?.flush() }
  }

  private func flush() {
    flushQueued = false
    var changed: [String: String] = [:]
    for slot in [email, password] where slot.field != nil {
      let text = slot.currentText
      if text != slot.lastSent {
        slot.lastSent = text
        changed[slot.name] = text
      }
    }
    if !changed.isEmpty { channel.invokeMethod("changed", arguments: changed) }
  }

  func controlTextDidChange(_ notification: Notification) {
    fieldValueMayHaveChanged()
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let control = notification.object as? NSControl, let slot = slot(for: control)
    else { return }
    fieldValueMayHaveChanged()
    if !slot.focused { return }
    slot.focused = false
    channel.invokeMethod("focusChanged", arguments: ["field": slot.name, "focused": false])
  }

  // Tab and Return between the two fields stay in AppKit; leaving the pair
  // goes through Dart's focus order.
  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard let slot = slot(for: control) else { return false }
    let isEmail = slot === email
    switch selector {
    case #selector(NSResponder.insertTab(_:)):
      if isEmail {
        window?.makeFirstResponder(password.field)
      } else {
        channel.invokeMethod("tab", arguments: ["field": slot.name, "forward": true])
      }
    case #selector(NSResponder.insertBacktab(_:)):
      if isEmail {
        channel.invokeMethod("tab", arguments: ["field": slot.name, "forward": false])
      } else {
        window?.makeFirstResponder(email.field)
      }
    case #selector(NSResponder.insertNewline(_:)):
      if isEmail {
        window?.makeFirstResponder(password.field)
      } else {
        flush()
        channel.invokeMethod("submitted", arguments: ["field": slot.name, "text": slot.currentText])
      }
    default:
      return false
    }
    return true
  }
}
