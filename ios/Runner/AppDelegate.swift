import Flutter
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SecretPasteboard") {
      SecretPasteboard.register(with: registrar.messenger())
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
