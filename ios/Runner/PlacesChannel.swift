import CoreLocation
import Flutter
import UIKit

// The Dart side is lib/insights/places_source.dart, which clusters visits and
// keeps them only in the sealed device files. Visits wait here in memory
// alone, never on disk, until Dart has sealed them: one reported while no
// Dart side runs, or before the journal key loads, is lost if the process
// ends first.
enum PlacesChannel {
  static let channelName = "com.screendead.penchant/places"
  private static var monitor: Monitor?
  private static var channel: FlutterMethodChannel?

  // Core Location shows the upgrade to Always at most once.
  private static let askedAlwaysKey = "places.askedAlways"

  // The Always prompt answered "Keep Only While Using" tells the delegate
  // nothing, so a wait ends when the app is active again, or after this.
  private static let promptTimeout: TimeInterval = 120

  /// At launch: the system relaunches the app for a visit, which reaches only
  /// a manager made again with its delegate.
  static func start() {
    let m = Monitor()
    monitor = m
    if m.allowed { m.manager.startMonitoringVisits() }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    PlacesChannel.channel = channel
    if monitor == nil { start() }
    channel.setMethodCallHandler { call, result in
      guard let m = monitor else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "access":
        result(m.access)
      case "requestAccess":
        m.requestAccess { result($0) }
      case "start":
        if m.allowed { m.manager.startMonitoringVisits() }
        result(nil)
      case "take":
        let flat = m.pending.flatMap { $0 }
        result(FlutterStandardTypedData(float64: flat.withUnsafeBufferPointer { Data(buffer: $0) }))
      case "ack":
        let count = ((call.arguments as? [String: Any])?["count"] as? NSNumber)?.intValue ?? 0
        m.pending.removeFirst(min(max(count, 0), m.pending.count))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // [arrival, departure, latitude, longitude, accuracy]; an unknown arrival
  // or departure (distantPast, distantFuture) is NaN.
  static func flat(_ visit: CLVisit) -> [Double] {
    let arrival = visit.arrivalDate == .distantPast ? .nan : (visit.arrivalDate.timeIntervalSince1970 * 1e6).rounded()
    let departure =
      visit.departureDate == .distantFuture ? .nan : (visit.departureDate.timeIntervalSince1970 * 1e6).rounded()
    return [
      arrival, departure, visit.coordinate.latitude, visit.coordinate.longitude, visit.horizontalAccuracy,
    ]
  }

  private final class Monitor: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var pending: [[Double]] = []
    private var waiting: [() -> Void] = []

    override init() {
      super.init()
      manager.delegate = self
    }

    var allowed: Bool {
      let s = manager.authorizationStatus
      return s == .authorizedAlways || s == .authorizedWhenInUse
    }

    var access: String {
      switch manager.authorizationStatus {
      case .authorizedAlways: return "always"
      case .authorizedWhenInUse: return "whenInUse"
      case .denied: return "denied"
      case .restricted: return "restricted"
      case .notDetermined: return "notDetermined"
      @unknown default: return "denied"
      }
    }

    // When In Use first; once allowed, the upgrade to Always, which Apple
    // asks for in that order.
    func requestAccess(_ done: @escaping (String) -> Void) {
      switch manager.authorizationStatus {
      case .notDetermined:
        wait(untilActive: false) { [weak self] in
          guard let self else { return }
          if self.manager.authorizationStatus == .authorizedWhenInUse {
            self.requestAlways(done)
          } else {
            done(self.access)
          }
        }
        manager.requestWhenInUseAuthorization()
      case .authorizedWhenInUse:
        requestAlways(done)
      default:
        done(access)
      }
    }

    private func requestAlways(_ done: @escaping (String) -> Void) {
      manager.startMonitoringVisits()
      if UserDefaults.standard.bool(forKey: PlacesChannel.askedAlwaysKey) {
        done(access)
        return
      }
      UserDefaults.standard.set(true, forKey: PlacesChannel.askedAlwaysKey)
      wait(untilActive: true) { [weak self] in done(self?.access ?? "denied") }
      manager.requestAlwaysAuthorization()
    }

    // Calls [then] once: on the next authorization change, or, with
    // [untilActive], when the app is active again after the prompt.
    private func wait(untilActive: Bool, then: @escaping () -> Void) {
      var called = false
      var observer: NSObjectProtocol?
      let once = {
        if called { return }
        called = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        then()
      }
      waiting.append(once)
      if untilActive {
        observer = NotificationCenter.default.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in once() }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + PlacesChannel.promptTimeout) { once() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      // Called once when the delegate is set, before any prompt.
      if manager.authorizationStatus == .notDetermined { return }
      if allowed { manager.startMonitoringVisits() }
      let woken = waiting
      waiting = []
      woken.forEach { $0() }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
      pending.append(PlacesChannel.flat(visit))
      PlacesChannel.channel?.invokeMethod("reported", arguments: nil)
    }
  }
}
