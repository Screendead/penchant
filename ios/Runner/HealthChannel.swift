import Flutter
import HealthKit

// The Dart side is lib/insights/health_source.dart. Read-only: nothing here
// writes to Health, and what it reads goes back to Dart and nowhere else.
// Days cross the channel as local "yyyy-MM-dd" strings so that neither side's
// time zone or a DST change can move a value to another day.
enum HealthChannel {
  static let channelName = "com.screendead.penchant/health"
  private static let store = HKHealthStore()

  private enum Window {
    // Local midnight to midnight.
    case day
    // Noon to noon, keyed by the day it ends on, like the sleep metrics.
    case night
  }

  private struct Statistic {
    let type: HKQuantityType
    let unit: HKUnit
    let options: HKStatisticsOptions
    var window = Window.day
  }

  private static func statistic(_ metric: String) -> Statistic? {
    let average = HKStatisticsOptions.discreteAverage
    let sum = HKStatisticsOptions.cumulativeSum
    let perMinute = HKUnit.count().unitDivided(by: .minute())
    switch metric {
    case "heartRateVariabilitySDNN":
      return Statistic(
        type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), options: average)
    case "restingHeartRate":
      return Statistic(type: HKQuantityType(.restingHeartRate), unit: perMinute, options: average)
    case "respiratoryRate":
      return Statistic(type: HKQuantityType(.respiratoryRate), unit: perMinute, options: average, window: .night)
    case "oxygenSaturation":
      return Statistic(type: HKQuantityType(.oxygenSaturation), unit: .percent(), options: average)
    case "appleSleepingWristTemperature":
      guard #available(iOS 16.0, *) else { return nil }
      return Statistic(
        type: HKQuantityType(.appleSleepingWristTemperature), unit: .degreeCelsius(), options: average,
        window: .night)
    case "stepCount":
      return Statistic(type: HKQuantityType(.stepCount), unit: .count(), options: sum)
    case "activeEnergyBurned":
      return Statistic(type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), options: sum)
    default:
      return nil
    }
  }

  private static let quantityMetrics = [
    "heartRateVariabilitySDNN", "restingHeartRate", "respiratoryRate", "oxygenSaturation",
    "appleSleepingWristTemperature", "stepCount", "activeEnergyBurned",
  ]

  private static var readTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
    for metric in quantityMetrics {
      if let s = statistic(metric) { types.insert(s.type) }
    }
    return types
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard HKHealthStore.isHealthDataAvailable() else {
        result(FlutterError(code: "unavailable", message: "Health data is unavailable on this device", details: nil))
        return
      }
      switch call.method {
      case "isAvailable":
        result(true)
      case "requestAuthorization":
        // Completes the same way whether the person allowed or refused each
        // type: HealthKit does not tell an app that read access was denied.
        store.requestAuthorization(toShare: [], read: readTypes) { success, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "authorization-failed", message: error.localizedDescription, details: nil))
            } else {
              result(success)
            }
          }
        }
      case "dailyValues":
        guard let args = call.arguments as? [String: Any],
          let metrics = args["metrics"] as? [String],
          let start = HealthDays.day(args["start"], calendar), let end = HealthDays.day(args["end"], calendar),
          start <= end
        else {
          result(FlutterError(code: "bad-arguments", message: "dailyValues takes metrics, start and end", details: nil))
          return
        }
        guard start < end else {
          result([])
          return
        }
        dailyValues(metrics: Set(metrics), start: start, end: end) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let rows): result(rows)
            case .failure(let error): result(flutterError(error))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // HealthKit refuses reads while the device is locked, since Health data is
  // protected, and before the authorization sheet has been shown. Either way
  // the caller must not read the silence as a day with no data.
  private static func flutterError(_ error: Error) -> FlutterError {
    let code: String
    switch (error as? HKError)?.code {
    case .errorDatabaseInaccessible: code = "database-inaccessible"
    case .errorAuthorizationNotDetermined: code = "not-determined"
    default: code = "query-failed"
    }
    return FlutterError(code: code, message: error.localizedDescription, details: nil)
  }

  private static func isNoData(_ error: Error) -> Bool {
    (error as? HKError)?.code == .errorNoData
  }

  private static var calendar: Calendar { Calendar.current }

  // Each row is ["date": "yyyy-MM-dd", "metric": id, "value": Double]. A day
  // with no samples has no row: no data is never a zero. If any query fails,
  // the whole call fails rather than answer with the rows of the others.
  private static func dailyValues(
    metrics: Set<String>, start: Date, end: Date,
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  ) {
    let group = DispatchGroup()
    let lock = NSLock()
    var rows: [[String: Any]] = []
    var firstError: Error?
    func finish(_ more: [[String: Any]], _ error: Error?) {
      lock.lock()
      if let error, !isNoData(error) {
        if firstError == nil { firstError = error }
      } else {
        rows.append(contentsOf: more)
      }
      lock.unlock()
      group.leave()
    }

    for metric in metrics {
      guard let s = statistic(metric) else { continue }
      let from = s.window == .night ? HealthDays.noon(before: start, calendar) : start
      let to = s.window == .night ? HealthDays.noon(before: end, calendar) : end
      group.enter()
      let query = HKStatisticsCollectionQuery(
        quantityType: s.type,
        quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to),
        options: s.options,
        anchorDate: from,
        intervalComponents: DateComponents(day: 1))
      query.initialResultsHandler = { _, collection, error in
        var found: [[String: Any]] = []
        collection?.enumerateStatistics(from: from, to: to) { stats, _ in
          let quantity = s.options == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
          guard let quantity, stats.startDate < to else { return }
          let date =
            s.window == .night
            ? HealthDays.nightKey(bucketStart: stats.startDate, calendar) : HealthDays.key(stats.startDate, calendar)
          found.append(["date": date, "metric": metric, "value": quantity.doubleValue(for: s.unit)])
        }
        finish(found, error)
      }
      store.execute(query)
    }

    let wantedSleep = HealthDays.sleepMetrics.filter { metrics.contains($0.id) }
    if !wantedSleep.isEmpty {
      group.enter()
      let (from, to) = HealthDays.sleepFetchWindow(start: start, end: end, calendar)
      let query = HKSampleQuery(
        sampleType: HKCategoryType(.sleepAnalysis),
        predicate: HKQuery.predicateForSamples(withStart: from, end: to), limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { _, samples, error in
        let sleep = ((samples as? [HKCategorySample]) ?? []).map {
          HealthDays.SleepSample(start: $0.startDate, end: $0.endDate, value: $0.value)
        }
        finish(HealthDays.sleepRows(sleep, metrics: wantedSleep, start: start, end: end, calendar), error)
      }
      store.execute(query)
    }

    group.notify(queue: .global(qos: .userInitiated)) {
      if let firstError {
        completion(.failure(firstError))
      } else {
        completion(.success(rows))
      }
    }
  }
}
