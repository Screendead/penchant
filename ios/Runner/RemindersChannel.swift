import EventKit
import Flutter

// The Dart side is lib/insights/reminders_source.dart. Read-only: nothing here
// writes to Reminders. Each reminder crosses the channel as its due and
// completion times alone; titles, notes, lists, places and alarms are never
// read into the answer.
enum RemindersChannel {
  static let channelName = "com.screendead.penchant/reminders"
  private static let store = EKEventStore()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result(access())
      case "requestAccess":
        requestAccess { granted in DispatchQueue.main.async { result(granted) } }
      case "reminders":
        reminders(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func access() -> String {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if #available(iOS 17.0, *) {
      switch status {
      case .fullAccess: return "full"
      case .writeOnly: return "writeOnly"
      case .denied: return "denied"
      case .restricted: return "restricted"
      case .notDetermined: return "notDetermined"
      default: return "denied"
      }
    }
    switch status {
    case .authorized: return "full"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    default: return "denied"
    }
  }

  private static func requestAccess(_ done: @escaping (Bool) -> Void) {
    let completion: EKEventStoreRequestAccessCompletionHandler = { granted, _ in
      // Reminders fetched before the answer stay empty until the store resets.
      store.reset()
      done(granted)
    }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToReminders(completion: completion)
    } else {
      store.requestAccess(to: .reminder, completion: completion)
    }
  }

  // Answers [due, completed, ...] in microseconds since 1970, NaN for a time a
  // reminder lacks, one pair per reminder in every list, done or not. One
  // with neither time is left out.
  private static func reminders(result: @escaping FlutterResult) {
    guard access() == "full" else {
      result(FlutterError(code: "not-allowed", message: nil, details: nil))
      return
    }
    let predicate = store.predicateForReminders(in: nil)
    store.fetchReminders(matching: predicate) { found in
      var flat: [Double] = []
      for reminder in found ?? [] {
        let due = reminder.dueDateComponents.flatMap { components in
          (components.calendar ?? Calendar.current).date(from: components)
        }
        let done = reminder.isCompleted ? reminder.completionDate : nil
        if due == nil && done == nil { continue }
        flat.append(micros(due))
        flat.append(micros(done))
      }
      let typed = FlutterStandardTypedData(float64: flat.withUnsafeBufferPointer { Data(buffer: $0) })
      DispatchQueue.main.async { result(typed) }
    }
  }

  private static func micros(_ date: Date?) -> Double {
    guard let date else { return .nan }
    return (date.timeIntervalSince1970 * 1e6).rounded()
  }
}
