import EventKit
import Flutter

// The Dart side is lib/insights/calendar_source.dart. Read-only: nothing here
// writes to the calendar. Each event crosses the channel as its start and end
// alone; titles, notes, places and attendees are never read into the answer.
enum CalendarChannel {
  static let channelName = "com.screendead.penchant/calendar"
  private static let store = EKEventStore()
  private static let queue = DispatchQueue(label: "com.screendead.penchant.calendar", qos: .userInitiated)

  // EventKit refuses a predicate spanning more than four years.
  private static let maxSpan: TimeInterval = 4 * 365 * 24 * 3600

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result(access())
      case "requestAccess":
        requestAccess { granted in DispatchQueue.main.async { result(granted) } }
      case "events":
        events(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func access() -> String {
    let status = EKEventStore.authorizationStatus(for: .event)
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
      // Events fetched before the answer stay empty until the store resets.
      store.reset()
      done(granted)
    }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: completion)
    } else {
      store.requestAccess(to: .event, completion: completion)
    }
  }

  // Answers [start, end, ...] in microseconds since 1970, sorted by start.
  // Drops all-day and cancelled events, and events the person declined.
  private static func events(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
      let startMicros = (args["start"] as? NSNumber)?.int64Value,
      let endMicros = (args["end"] as? NSNumber)?.int64Value
    else {
      result(FlutterError(code: "bad-arguments", message: nil, details: nil))
      return
    }
    guard access() == "full" else {
      result(FlutterError(code: "not-allowed", message: nil, details: nil))
      return
    }
    let start = Date(timeIntervalSince1970: TimeInterval(startMicros) / 1e6)
    let end = Date(timeIntervalSince1970: TimeInterval(endMicros) / 1e6)
    guard start < end, end.timeIntervalSince(start) <= maxSpan else {
      result(FlutterError(code: "bad-arguments", message: nil, details: nil))
      return
    }
    // events(matching:) is synchronous.
    queue.async {
      let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
      var flat: [Double] = []
      for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate }) {
        if event.isAllDay || event.status == .canceled { continue }
        if let me = event.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined {
          continue
        }
        guard let s = event.startDate, let e = event.endDate, s < e else { continue }
        flat.append((s.timeIntervalSince1970 * 1e6).rounded())
        flat.append((e.timeIntervalSince1970 * 1e6).rounded())
      }
      let typed = FlutterStandardTypedData(float64: flat.withUnsafeBufferPointer { Data(buffer: $0) })
      DispatchQueue.main.async { result(typed) }
    }
  }
}
