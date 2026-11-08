import AppIntents
import WidgetKit

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

// The Dart side is lib/widget_bridge/widget_bridge.dart; the widgets read the
// snapshot in ios/PenchantWidgets/Snapshot.swift and leave logs in
// ios/PenchantWidgets/LogQueue.swift. The macOS app compiles this file too.
enum WidgetBridge {
  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: "com.screendead.penchant/widgets", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let defaults = UserDefaults(suiteName: appGroup) else {
        result(FlutterError(code: "no-app-group", message: "App Group \(appGroup) is unavailable", details: nil))
        return
      }
      switch call.method {
      case "save":
        guard let snapshot = call.arguments as? String else {
          result(FlutterError(code: "bad-arguments", message: "save takes the snapshot as a string", details: nil))
          return
        }
        defaults.set(snapshot, forKey: snapshotKey)
        if #available(iOS 17.0, macOS 14.0, *) {
          PenchantShortcuts.updateAppShortcutParameters()
        }
      case "clear":
        defaults.removeObject(forKey: snapshotKey)
        LastLog.save(nil)
      case "pendingLogs":
        let data = (try? JSONEncoder().encode(LogQueue.read())) ?? Data("[]".utf8)
        result(String(decoding: data, as: UTF8.self))
        return
      case "removeLogs":
        guard let json = call.arguments as? String,
          let done = try? JSONDecoder().decode([QueuedLog].self, from: Data(json.utf8))
        else {
          result(FlutterError(code: "bad-arguments", message: "removeLogs takes the logs as JSON", details: nil))
          return
        }
        guard LogQueue.remove(done) else {
          result(FlutterError(code: "queue-unwritable", message: "Could not update the log queue", details: nil))
          return
        }
        // On to the reload: the snapshot may already count these entries,
        // and no later save follows if the acknowledgement changes nothing.
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      WidgetCenter.shared.reloadAllTimelines()
      result(nil)
    }
  }
}
