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

  // Session types, read as minutes a day (HealthDays.sessionMinuteRows): only
  // each session's start and end, never a workout's type, route or metadata.
  private static func sessionType(_ metric: String) -> HKSampleType? {
    switch metric {
    case "workoutMinutes": return HKObjectType.workoutType()
    case "mindfulMinutes": return HKCategoryType(.mindfulSession)
    default: return nil
    }
  }

  private static let sessionMetrics = ["workoutMinutes", "mindfulMinutes"]

  // Days with menstrual flow (HealthDays.flowDayRows), for the insights engine
  // to infer cycle phase from and hold fixed; never an outcome or shown.
  private static let menstrualFlow = "menstrualFlow"

  // Raw samples, for the hours around an entry. Units as the daily path's.
  private static func sampleType(_ metric: String) -> (type: HKQuantityType, unit: HKUnit)? {
    switch metric {
    case "heartRate": return (HKQuantityType(.heartRate), HKUnit.count().unitDivided(by: .minute()))
    case "heartRateVariabilitySDNN": return (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli))
    case "respiratoryRate": return (HKQuantityType(.respiratoryRate), HKUnit.count().unitDivided(by: .minute()))
    case "stepCount": return (HKQuantityType(.stepCount), .count())
    default: return nil
    }
  }

  static let maxSamplesPerCall = 20_000
  // HealthSampleMetric.bed: spans rather than readings, one page.
  private static let bedMetric = "bed"
  private static let sleepingHeartRate = "sleepingHeartRate"

  // healthReadTypesVersion in lib/providers/insights_provider.dart counts
  // changes to this set; raise it with each one.
  private static var readTypes: Set<HKObjectType> {
    var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRate)]
    for metric in quantityMetrics {
      if let s = statistic(metric) { types.insert(s.type) }
    }
    for metric in sessionMetrics {
      if let type = sessionType(metric) { types.insert(type) }
    }
    types.insert(HKCategoryType(.menstrualFlow))
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
              if success { Sync.reset() }
              result(success)
            }
          }
        }
      case "changes":
        guard let args = call.arguments as? [String: Any], let metrics = args["metrics"] as? [String] else {
          result(FlutterError(code: "bad-arguments", message: "changes takes metrics", details: nil))
          return
        }
        Sync.changes(metrics: metrics) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let changes): result(changes)
            case .failure(let error): result(flutterError(error))
            }
          }
        }
      case "changesHandled":
        guard let args = call.arguments as? [String: Any], let generation = (args["generation"] as? NSNumber)?.intValue
        else {
          result(FlutterError(code: "bad-arguments", message: "changesHandled takes generation", details: nil))
          return
        }
        Sync.handled(generation: generation)
        result(nil)
      case "requestStatus":
        // .shouldRequest once readTypes holds a type the person was never
        // asked about; the sheet then shows only those types.
        store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "status-failed", message: error.localizedDescription, details: nil))
              return
            }
            switch status {
            case .shouldRequest: result("shouldRequest")
            case .unnecessary: result("unnecessary")
            default: result("unknown")
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
      case "samples":
        guard let args = call.arguments as? [String: Any],
          let metric = args["metric"] as? String, metric == bedMetric || sampleType(metric) != nil,
          let from = (args["start"] as? NSNumber)?.int64Value, let to = (args["end"] as? NSNumber)?.int64Value,
          let limit = (args["limit"] as? NSNumber)?.intValue, limit >= 1, limit <= maxSamplesPerCall
        else {
          result(
            FlutterError(code: "bad-arguments", message: "samples takes metric, start, end and limit", details: nil))
          return
        }
        guard from < to else {
          result(["samples": FlutterStandardTypedData(float64: Data()), "next": NSNull()])
          return
        }
        let reply: (Result<[String: Any], Error>) -> Void = { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let page): result(page)
            case .failure(let error): result(flutterError(error))
            }
          }
        }
        if let type = sampleType(metric) {
          samples(type: type, from: from, to: to, limit: limit, completion: reply)
        } else {
          bedSpans(from: from, to: to, completion: reply)
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

  private static func isNotDetermined(_ error: Error) -> Bool {
    (error as? HKError)?.code == .errorAuthorizationNotDetermined
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

    for metric in metrics {
      guard let type = sessionType(metric) else { continue }
      group.enter()
      let query = HKSampleQuery(
        sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end),
        limit: HKObjectQueryNoLimit, sortDescriptors: nil
      ) { _, samples, error in
        // Someone who connected Health before this type joined readTypes has
        // not been asked for it; taken to fail as not determined (unchecked on
        // a device), which costs this metric alone until the sheet is shown.
        if let error, isNotDetermined(error) {
          finish([], nil)
          return
        }
        let sessions = (samples ?? []).map { ($0.startDate, $0.endDate) }
        finish(HealthDays.sessionMinuteRows(sessions, metric: metric, start: start, end: end, calendar), error)
      }
      store.execute(query)
    }

    if metrics.contains(menstrualFlow) {
      group.enter()
      let query = HKSampleQuery(
        sampleType: HKCategoryType(.menstrualFlow), predicate: HKQuery.predicateForSamples(withStart: start, end: end),
        limit: HKObjectQueryNoLimit, sortDescriptors: nil
      ) { _, samples, error in
        // As for the session types: asked of someone who connected before it
        // joined readTypes, it costs this metric alone.
        if let error, isNotDetermined(error) {
          finish([], nil)
          return
        }
        let days = (samples ?? []).compactMap { $0 as? HKCategorySample }.map { (start: $0.startDate, value: $0.value) }
        finish(HealthDays.flowDayRows(days, metric: menstrualFlow, start: start, end: end, calendar), error)
      }
      store.execute(query)
    }

    let wantedSleep = HealthDays.sleepMetrics.filter { metrics.contains($0.id) }
    let wantedTiming = HealthDays.sleepTimingMetrics.intersection(metrics)
    let wantsSleepingHeartRate = metrics.contains(sleepingHeartRate)
    if !wantedSleep.isEmpty || !wantedTiming.isEmpty || wantsSleepingHeartRate {
      group.enter()
      let (from, to) = HealthDays.sleepFetchWindow(start: start, end: end, calendar)
      let query = HKSampleQuery(
        sampleType: HKCategoryType(.sleepAnalysis),
        predicate: HKQuery.predicateForSamples(withStart: from, end: to), limit: HKObjectQueryNoLimit,
        sortDescriptors: nil
      ) { _, samples, error in
        let sleep = sleepSamples(samples)
        let sleepRows =
          HealthDays.sleepRows(sleep, metrics: wantedSleep, start: start, end: end, calendar)
          + HealthDays.sleepTimingRows(sleep, metrics: wantedTiming, start: start, end: end, calendar)
        let asleep = HealthDays.asleepIntervals(HealthDays.nights(sleep, start: start, end: end, calendar))
        guard wantsSleepingHeartRate, error == nil, !asleep.isEmpty else {
          finish(sleepRows, error)
          return
        }
        nightHeartRate(asleep: asleep) { heartRows, heartError in
          // Someone who connected Health before heart rate joined readTypes
          // has not been asked for it. HealthKit is taken to fail that read as
          // not determined (unchecked on a device); it costs sleepingHeartRate
          // alone, not the sleep rows and every other metric with it.
          if (heartError as? HKError)?.code == .errorAuthorizationNotDetermined {
            finish(sleepRows, nil)
          } else {
            finish(sleepRows + heartRows, heartError)
          }
        }
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

  private static func sleepSamples(_ samples: [HKSample]?) -> [HealthDays.SleepSample] {
    ((samples as? [HKCategorySample]) ?? []).map { sample in
      let source = sample.sourceRevision.source.bundleIdentifier
      let product = sample.sourceRevision.productType
      return HealthDays.SleepSample(
        start: sample.startDate, end: sample.endDate, value: sample.value, source: source,
        watch: product?.hasPrefix("Watch") == true && source.hasPrefix("com.apple.health"))
    }
  }

  // The spans in bed or asleep that start in [from, to), as one page of
  // samples with value 0, each night from the source the sleep metrics use.
  // A year of nights is a few thousand samples, so there is no paging.
  private static func bedSpans(
    from: Int64, to: Int64, completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    let first = calendar.startOfDay(for: HealthDays.date(micros: from))
    let last = HealthDays.adding(days: 2, to: calendar.startOfDay(for: HealthDays.date(micros: to)), calendar)
    let (fetchFrom, fetchTo) = HealthDays.sleepFetchWindow(start: first, end: last, calendar)
    let query = HKSampleQuery(
      sampleType: HKCategoryType(.sleepAnalysis),
      predicate: HKQuery.predicateForSamples(withStart: fetchFrom, end: fetchTo), limit: HKObjectQueryNoLimit,
      sortDescriptors: nil
    ) { _, samples, error in
      if let error, !isNoData(error) {
        completion(.failure(error))
        return
      }
      let nights = HealthDays.nights(sleepSamples(samples), start: first, end: last, calendar)
      let spans = HealthDays.bedSpans(nights).filter {
        let start = HealthDays.micros($0.0)
        return start >= from && start < to
      }
      let flat = HealthDays.flatten(spans.map { HealthDays.QuantitySample(start: $0.0, end: $0.1, value: 0) })
      let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
      completion(.success(["samples": FlutterStandardTypedData(float64: data), "next": NSNull()]))
    }
    store.execute(query)
  }

  // Reads only the heart rate inside each night's asleep span, so a year of
  // nights is not a year of heart rate.
  private static func nightHeartRate(
    asleep: [String: [(Date, Date)]], completion: @escaping ([[String: Any]], Error?) -> Void
  ) {
    let predicate = NSCompoundPredicate(
      orPredicateWithSubpredicates: HealthDays.spans(asleep).map {
        HKQuery.predicateForSamples(withStart: $0.0, end: $0.1)
      })
    let unit = HKUnit.count().unitDivided(by: .minute())
    let query = HKSampleQuery(
      sampleType: HKQuantityType(.heartRate), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
    ) { _, samples, error in
      let heart = ((samples as? [HKQuantitySample]) ?? []).map {
        HealthDays.QuantitySample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
      }
      completion(HealthDays.meanInsideRows(heart, asleep: asleep, metric: sleepingHeartRate), error)
    }
    store.execute(query)
  }

  // One page: up to limit samples whose start is in [from, to), sorted by
  // start, as ["samples": [start, end, value, ...] in microseconds since 1970,
  // "next": the start to read the next page from, or null when this is the
  // last]. The bounds are on the start alone, unlike predicateForSamples's
  // overlap, so a long sample begun before from is not read twice.
  private static func samples(
    type: (type: HKQuantityType, unit: HKUnit), from: Int64, to: Int64, limit: Int,
    completion: @escaping (Result<[String: Any], Error>) -> Void
  ) {
    let bounds = HealthDays.queryBounds(from: from, to: to)
    let predicate = NSPredicate(
      format: "%K >= %@ AND %K < %@",
      HKPredicateKeyPathStartDate, bounds.lower as NSDate,
      HKPredicateKeyPathStartDate, bounds.upper as NSDate)
    let query = HKSampleQuery(
      sampleType: type.type, predicate: predicate, limit: limit,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    ) { _, samples, error in
      if let error, !isNoData(error) {
        completion(.failure(error))
        return
      }
      let read = ((samples as? [HKQuantitySample]) ?? []).map {
        HealthDays.QuantitySample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: type.unit))
      }
      guard let page = HealthDays.page(read, from: from, to: to, limit: limit) else {
        completion(.failure(HKError(.errorInvalidArgument)))
        return
      }
      let flat = HealthDays.flatten(page.samples)
      let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
      completion(
        .success([
          "samples": FlutterStandardTypedData(float64: data),
          "next": page.next.map { NSNumber(value: $0) } ?? NSNull(),
        ]))
    }
    store.execute(query)
  }
}

// Anchored sync: which days of which metrics changed since Dart last read
// them, kept in Caches (not backed up, so no Health-derived state reaches
// iCloud) with each type's anchor. Observer queries with background delivery
// mark changes while the app is closed, so an open of Insights reads only
// those days. Work runs one job at a time on the queue, each loading and
// saving the state, so an observer's job and Dart's call never interleave.
extension HealthChannel {
  enum Sync {
    private static let queue = DispatchQueue(label: "com.screendead.penchant.health-sync", qos: .utility)
    // Touched on queue only.
    private static var observed: Set<String> = []
    private static let pageLimit = 10_000
    // A first anchor comes from the samples of this many recent days, so the
    // first sync does not read a type's whole history to find where it ends.
    private static let seedDays = 7.0

    private static var stateURL: URL? {
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("health-sync.json")
    }

    private static func load() -> HealthDays.SyncState {
      guard let url = stateURL, let data = try? Data(contentsOf: url),
        let state = try? JSONDecoder().decode(HealthDays.SyncState.self, from: data)
      else { return HealthDays.SyncState() }
      return state
    }

    private static func save(_ state: HealthDays.SyncState) {
      guard let url = stateURL, let data = try? JSONEncoder().encode(state) else { return }
      try? data.write(to: url, options: .atomic)
    }

    private static func types(for metric: String) -> [HKSampleType] {
      if let s = HealthChannel.statistic(metric) { return [s.type] }
      if let type = HealthChannel.sessionType(metric) { return [type] }
      if metric == HealthChannel.menstrualFlow { return [HKCategoryType(.menstrualFlow)] }
      let sleep = HKCategoryType(.sleepAnalysis)
      if metric == HealthChannel.sleepingHeartRate { return [sleep, HKQuantityType(.heartRate)] }
      if HealthDays.sleepMetrics.contains(where: { $0.id == metric }) || HealthDays.sleepTimingMetrics.contains(metric) {
        return [sleep]
      }
      return []
    }

    private static func typesByID(_ metrics: [String]) -> [String: (type: HKSampleType, metrics: [String])] {
      var out: [String: (type: HKSampleType, metrics: [String])] = [:]
      for metric in metrics {
        for type in types(for: metric) {
          out[type.identifier, default: (type: type, metrics: [])].metrics.append(metric)
        }
      }
      return out
    }

    private static func anchored(
      _ type: HKSampleType, predicate: NSPredicate?, anchor: HKQueryAnchor?, limit: Int
    ) -> (samples: [HKSample], deleted: Int, anchor: HKQueryAnchor?, error: Error?) {
      let done = DispatchSemaphore(value: 0)
      var out: (samples: [HKSample], deleted: Int, anchor: HKQueryAnchor?, error: Error?) = ([], 0, nil, nil)
      let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: limit) {
        _, samples, deleted, newAnchor, error in
        out = (samples ?? [], deleted?.count ?? 0, newAnchor, error)
        done.signal()
      }
      HealthChannel.store.execute(query)
      done.wait()
      return out
    }

    // Reads every change to type since its anchor into state, page by page,
    // each page's marks saved with its anchor. A deletion names no day, so it
    // marks the metrics whole. With no anchor yet the metrics are read whole
    // and the anchor comes from recent samples: changes after it are seen,
    // and an older one seen twice only rereads a day.
    private static func catchUp(_ type: HKSampleType, metrics: [String], _ state: inout HealthDays.SyncState)
      -> Error?
    {
      let id = type.identifier
      var anchor = state.anchors[id].flatMap {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
      }
      if anchor == nil {
        let since = Date().addingTimeInterval(-seedDays * 24 * 60 * 60)
        let seed = anchored(
          type, predicate: HKQuery.predicateForSamples(withStart: since, end: nil), anchor: nil,
          limit: HKObjectQueryNoLimit)
        if let error = seed.error, !tolerated(error) { return error }
        state.markWhole(metrics)
        if let next = seed.anchor,
          let data = try? NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true)
        {
          state.anchors[id] = data
        }
        return nil
      }
      while true {
        let page = anchored(type, predicate: nil, anchor: anchor, limit: pageLimit)
        if let error = page.error { return tolerated(error) ? nil : error }
        if page.deleted > 0 { state.markWhole(metrics) }
        var keys = Set<String>()
        for sample in page.samples {
          keys.formUnion(HealthDays.touchedKeys(start: sample.startDate, end: sample.endDate, HealthChannel.calendar))
        }
        if !keys.isEmpty { state.mark(metrics, keys: keys.sorted()) }
        if let next = page.anchor,
          let data = try? NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true)
        {
          state.anchors[id] = data
          anchor = next
        }
        save(state)
        if page.samples.count + page.deleted < pageLimit || page.anchor == nil { return nil }
      }
    }

    // A type never asked for (one added to readTypes since the sheet was last
    // shown) leaves its metrics whole with no anchor; its daily read answers
    // for it, so one such type does not fail every other's changes.
    private static func tolerated(_ error: Error) -> Bool {
      HealthChannel.isNoData(error) || HealthChannel.isNotDetermined(error)
    }

    // ["generation": Int, "days": [metric: [day key]], "whole": [metric]]:
    // what changed since the last handled generation, for the metrics asked.
    static func changes(metrics: [String], completion: @escaping (Result<[String: Any], Error>) -> Void) {
      queue.async {
        var state = load()
        let wanted = Array(Set(metrics)).sorted()
        state.metrics = wanted
        var failure: Error?
        for (_, entry) in typesByID(wanted).sorted(by: { $0.key < $1.key }) {
          if let error = catchUp(entry.type, metrics: entry.metrics, &state) {
            failure = error
            break
          }
        }
        save(state)
        observe(state)
        if let failure {
          completion(.failure(failure))
          return
        }
        let pending = state.pending(wanted)
        completion(.success(["generation": state.generation, "days": pending.days, "whole": pending.whole]))
      }
    }

    static func handled(generation: Int) {
      queue.async {
        var state = load()
        state.handled(through: generation)
        save(state)
      }
    }

    // After the Health sheet: a type just allowed holds history the anchor
    // has passed, so every metric is read whole again.
    static func reset() {
      queue.async {
        var state = load()
        state.anchors = [:]
        state.markWhole(state.metrics)
        save(state)
      }
    }

    // From application(_:didFinishLaunchingWithOptions:), as background
    // delivery requires; nothing until Dart has asked for changes once.
    static func start() {
      guard HKHealthStore.isHealthDataAvailable() else { return }
      queue.async { observe(load()) }
    }

    // Hourly at most: stepCount is capped there anyway, and a sleep or a
    // morning reading lands well before the page is next opened.
    private static func observe(_ state: HealthDays.SyncState) {
      for (id, entry) in typesByID(state.metrics) where !observed.contains(id) {
        observed.insert(id)
        let query = HKObserverQuery(sampleType: entry.type, predicate: nil) { _, done, error in
          guard error == nil else {
            done()
            return
          }
          queue.async {
            var state = load()
            let metrics = typesByID(state.metrics)[id]?.metrics ?? []
            if !metrics.isEmpty { _ = catchUp(entry.type, metrics: metrics, &state) }
            save(state)
            done()
          }
        }
        HealthChannel.store.execute(query)
        HealthChannel.store.enableBackgroundDelivery(for: entry.type, frequency: .hourly) { _, _ in }
      }
    }
  }
}
