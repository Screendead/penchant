import Flutter
import LocalAuthentication
import UIKit
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RemindersChannel") {
      RemindersChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlacesChannel") {
      PlacesChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotosChannel") {
      PhotosChannel.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecretPasteboard") {
      SecretPasteboard.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceAuth") {
      DeviceAuth.register(with: registrar.messenger())
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
