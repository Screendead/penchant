import Flutter
import HealthKit

// The Dart side is lib/insights/health_source.dart. Read-only: nothing here
// writes to Health, and what it reads goes back to Dart and nowhere else.
// Days cross the channel as local "yyyy-MM-dd" strings so that neither side's
// time zone or a DST change can move a value to another day.
enum HealthChannel {
  static let channelName = "com.screendead.penchant/health"
  private static let store = HKHealthStore()

  private struct Statistic {
    let type: HKQuantityType
    let unit: HKUnit
    let options: HKStatisticsOptions
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
      return Statistic(type: HKQuantityType(.respiratoryRate), unit: perMinute, options: average)
    case "oxygenSaturation":
      return Statistic(type: HKQuantityType(.oxygenSaturation), unit: .percent(), options: average)
    case "appleSleepingWristTemperature":
      guard #available(iOS 16.0, *) else { return nil }
      return Statistic(
        type: HKQuantityType(.appleSleepingWristTemperature), unit: .degreeCelsius(), options: average)
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

  // HKCategoryValueSleepAnalysis raw values, which are stable across releases:
  // inBed 0, asleepUnspecified (iOS 15's asleep) 1, awake 2, asleepCore 3,
  // asleepDeep 4, asleepREM 5. The named cases for 3 to 5 need iOS 16.
  private static let sleepMetrics: [(id: String, values: Set<Int>)] = [
    ("sleepInBed", [0]),
    ("sleepAsleep", [1, 3, 4, 5]),
    ("sleepAwake", [2]),
    ("sleepCore", [3]),
    ("sleepDeep", [4]),
    ("sleepREM", [5]),
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
          let start = day(args["start"]), let end = day(args["end"]), start < end
        else {
          result(FlutterError(code: "bad-arguments", message: "dailyValues takes metrics, start and end", details: nil))
          return
        }
        dailyValues(metrics: Set(metrics), start: start, end: end) { rows in
          DispatchQueue.main.async { result(rows) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static var calendar: Calendar { Calendar.current }

  private static func day(_ value: Any?) -> Date? {
    guard let parts = (value as? String)?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else {
      return nil
    }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }

  private static func key(_ date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  // Each row is ["date": "yyyy-MM-dd", "metric": id, "value": Double]. A day
  // with no samples has no row: no data is never a zero.
  private static func dailyValues(
    metrics: Set<String>, start: Date, end: Date, completion: @escaping ([[String: Any]]) -> Void
  ) {
    let group = DispatchGroup()
    let lock = NSLock()
    var rows: [[String: Any]] = []
    func add(_ more: [[String: Any]]) {
      lock.lock()
      rows.append(contentsOf: more)
      lock.unlock()
    }

    for metric in metrics {
      guard let s = statistic(metric) else { continue }
      group.enter()
      let query = HKStatisticsCollectionQuery(
        quantityType: s.type,
        quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
        options: s.options,
        anchorDate: start,
        intervalComponents: DateComponents(day: 1))
      query.initialResultsHandler = { _, collection, _ in
        var found: [[String: Any]] = []
        collection?.enumerateStatistics(from: start, to: end) { stats, _ in
          let quantity = s.options == .cumulativeSum ? stats.sumQuantity() : stats.averageQuantity()
          if let quantity {
            found.append(["date": key(stats.startDate), "metric": metric, "value": quantity.doubleValue(for: s.unit)])
          }
        }
        add(found)
        group.leave()
      }
      store.execute(query)
    }

    let wantedSleep = sleepMetrics.filter { metrics.contains($0.id) }
    if !wantedSleep.isEmpty {
      group.enter()
      sleepValues(wantedSleep, start: start, end: end) { found in
        add(found)
        group.leave()
      }
    }

    group.notify(queue: .global(qos: .userInitiated)) { completion(rows) }
  }

  // A night belongs to the local day it ends on: the value for 2026-11-08 is
  // the sleep that ended that morning. Samples that overlap, as a Watch's and
  // a phone's do, are merged per stage before their minutes are summed.
  private static func sleepValues(
    _ wanted: [(id: String, values: Set<Int>)], start: Date, end: Date,
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
    let query = HKSampleQuery(
      sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, _ in
      var byNight: [String: [HKCategorySample]] = [:]
      for sample in (samples as? [HKCategorySample]) ?? [] where sample.endDate < end {
        byNight[key(calendar.startOfDay(for: sample.endDate)), default: []].append(sample)
      }
      var found: [[String: Any]] = []
      for (night, samples) in byNight {
        for metric in wanted {
          let intervals = samples.filter { metric.values.contains($0.value) }.map { ($0.startDate, $0.endDate) }
          guard !intervals.isEmpty else { continue }
          found.append(["date": night, "metric": metric.id, "value": mergedMinutes(intervals)])
        }
      }
      completion(found)
    }
    store.execute(query)
  }

  private static func mergedMinutes(_ intervals: [(Date, Date)]) -> Double {
    var total: TimeInterval = 0
    var current: (Date, Date)?
    for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
      if let c = current, interval.0 <= c.1 {
        current = (c.0, max(c.1, interval.1))
      } else {
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        current = interval
      }
    }
    if let c = current { total += c.1.timeIntervalSince(c.0) }
    return total / 60
  }
}
