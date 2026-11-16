import Flutter
import Foundation

// The Dart side is lib/night_out/night_out_bridge.dart; the Live Activity is
// ios/PenchantWidgets/NightOut.swift. A night needs iOS 17, where the widget
// extension and its interactive buttons exist.
enum NightChannel {
  static let channelName = "com.screendead.penchant/night_out"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 17.0, *) else {
        if call.method == "status" {
          result(["supported": false, "enabled": false])
        } else {
          result(FlutterMethodNotImplemented)
        }
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "status":
        Task { @MainActor in
          let night = await NightOut.tidy(uid: args["uid"] as? String)
          result(["supported": true, "enabled": NightOut.enabled, "night": night.map(encode) as Any])
        }
      case "start":
        guard let uid = args["uid"] as? String, let viceID = args["viceID"] as? String,
          let base = (args["base"] as? NSNumber)?.doubleValue
        else {
          result(FlutterError(code: "bad-arguments", message: "start takes uid, viceID and base", details: nil))
          return
        }
        do {
          let night = try NightOut.start(
            uid: uid, viceID: viceID, habit: args["habit"] as? String, slot: args["slot"] as? Int, base: base)
          result(encode(night))
        } catch NightError.alreadyRunning {
          result(FlutterError(code: "already-running", message: nil, details: nil))
        } catch {
          // ActivityKit's own refusal: Live Activities turned off, or too many.
          result(FlutterError(code: "refused", message: "\(error)", details: nil))
        }
      case "reconcile":
        let base = (args["base"] as? NSNumber)?.doubleValue ?? 0
        let seen = Set(args["seen"] as? [String] ?? [])
        Task { @MainActor in
          let night = await NightOut.reconcile(uid: args["uid"] as? String, base: base, seen: seen)
          result(night.map(encode) as Any)
        }
      case "end":
        Task { @MainActor in
          await NightOut.end()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func encode(_ night: NightRecord) -> [String: Any] {
    [
      "id": night.id,
      "viceID": night.viceID,
      "start": (night.start.timeIntervalSince1970 * 1000).rounded(),
      "endBy": (night.endBy.timeIntervalSince1970 * 1000).rounded(),
      "showsHabit": night.showsHabit,
      "count": night.count,
    ]
  }
}
