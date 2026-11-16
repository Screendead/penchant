import Flutter
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications hears taps on the daily reminder through
    // the app delegate, which FlutterAppDelegate forwards to plugins.
    UNUserNotificationCenter.current().delegate = self
    BackgroundFlush.register()
    HealthChannel.Sync.start()
    PlacesChannel.start()
    // A night the app did not end (its morning passed, the person removed it
    // from the Lock Screen, another account signed in) ends at launch.
    if #available(iOS 17.0, *) {
      Task { await NightOut.tidy(uid: Snapshot.load()?.uid) }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WidgetBridge") {
      QueueListener.start(WidgetBridge.register(with: registrar), registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EntryPrompt") {
      EntryPrompt.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthChannel") {
      HealthChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CalendarChannel") {
      CalendarChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SentenceEmbeddingChannel") {
      SentenceEmbeddingChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RemindersChannel") {
      RemindersChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechChannel") {
      SpeechChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlacesChannel") {
      PlacesChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotosChannel") {
      PhotosChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LabelChannel") {
      LabelChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NightChannel") {
      NightChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecretPasteboard") {
      SecretPasteboard.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceAuth") {
      DeviceAuth.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackupFiles") {
      BackupFiles.shared.register(with: registrar.messenger())
    }
  }
}

// Info.plist names it as the scene delegate. A widget's "What was going on?"
// link opens the app with an EntryLink URL: at launch in the connection
// options, after in openURLContexts. FlutterDeepLinkingEnabled is false in
// Info.plist, so Flutter never pushes one as a route.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
  ) {
    if FlutterSceneDelegate.instancesRespond(to: #selector(UISceneDelegate.scene(_:willConnectTo:options:))) {
      super.scene(scene, willConnectTo: session, options: connectionOptions)
    }
    for context in connectionOptions.urlContexts {
      EntryPrompt.open(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let others = URLContexts.filter { !EntryPrompt.open($0.url) }
    if !others.isEmpty,
      FlutterSceneDelegate.instancesRespond(to: #selector(UISceneDelegate.scene(_:openURLContexts:)))
    {
      super.scene(scene, openURLContexts: others)
    }
  }
}

// The Dart side is lib/journal_key/secret_clipboard.dart. localOnly keeps the
// item off Universal Clipboard; the system removes it at the expiration date.
enum SecretPasteboard {
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
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(TimeInterval(seconds)),
        ])
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

// The Dart side is lib/backup/backup_service.dart. The export panel needs a
// file to copy, so saving writes one into a fixed folder in tmp and removes
// it when the panel closes, saved or cancelled, and again at launch and before
// each save, in case the app was killed with the panel open. Picking reads
// the chosen file where it is, through security-scoped access, and copies
// nothing.
final class BackupFiles: NSObject, UIDocumentPickerDelegate {
  static let shared = BackupFiles()

  private var pending: FlutterResult?
  private var picking = false
  private let exportFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("penchant-backup-export", isDirectory: true)

  func register(with messenger: FlutterBinaryMessenger) {
    try? FileManager.default.removeItem(at: exportFolder)
    let channel = FlutterMethodChannel(
      name: "com.screendead.penchant/backup_files", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private static func presenter() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "save" || call.method == "pick" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let presenter = Self.presenter(), !(presenter is UIDocumentPickerViewController)
    else {
      result(FlutterError(code: "busy", message: "No panel can be shown now", details: nil))
      return
    }
    // A call whose panel closed without a callback must not block later ones.
    if pending != nil {
      finish(FlutterError(code: "superseded", message: "Another panel opened", details: nil))
    }
    if call.method == "pick" {
      picking = true
      pending = result
      let panel = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
      panel.allowsMultipleSelection = false
      panel.delegate = self
      presenter.present(panel, animated: true)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let bytes = args["bytes"] as? FlutterStandardTypedData,
      let name = args["name"] as? String
    else {
      result(FlutterError(code: "arguments", message: "save needs bytes and a name", details: nil))
      return
    }
    try? FileManager.default.removeItem(at: exportFolder)
    do {
      try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
      let file = exportFolder.appendingPathComponent((name as NSString).lastPathComponent)
      try bytes.data.write(to: file, options: [.completeFileProtection])
      picking = false
      pending = result
      let panel = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      panel.delegate = self
      presenter.present(panel, animated: true)
    } catch {
      try? FileManager.default.removeItem(at: exportFolder)
      result(FlutterError(code: "write", message: error.localizedDescription, details: nil))
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard picking else {
      finish(true)
      return
    }
    guard let url = urls.first else {
      finish(nil)
      return
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    // The coordinator waits for iCloud Drive to download a file not yet here.
    var coordinationError: NSError?
    var read: Result<Data, Error>?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      readable in
      read = Result { try Data(contentsOf: readable) }
    }
    switch read {
    case .success(let data):
      finish(FlutterStandardTypedData(bytes: data))
    case .failure(let error):
      finish(FlutterError(code: "read", message: error.localizedDescription, details: nil))
    case nil:
      finish(
        FlutterError(
          code: "read", message: coordinationError?.localizedDescription ?? "Not read",
          details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(picking ? nil : false)
  }

  private func finish(_ value: Any?) {
    try? FileManager.default.removeItem(at: exportFolder)
    let result = pending
    pending = nil
    result?(value)
  }
}
