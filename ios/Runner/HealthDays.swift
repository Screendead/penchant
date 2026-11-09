import Foundation

// The day, night and sample arithmetic behind HealthChannel.swift. It imports
// no HealthKit, so tools/health-days.test.sh can compile and test it on its own.
enum HealthDays {
  struct SleepSample {
    let start: Date
    let end: Date
    let value: Int
  }

  struct QuantitySample {
    let start: Date
    let end: Date
    let value: Double
  }

  // HKCategoryValueSleepAnalysis raw values, which are stable across releases:
  // inBed 0, asleepUnspecified (iOS 15's asleep) 1, awake 2, asleepCore 3,
  // asleepDeep 4, asleepREM 5. The named cases for 3 to 5 need iOS 16.
  static let asleepValues: Set<Int> = [1, 3, 4, 5]
  static let sleepMetrics: [(id: String, values: Set<Int>)] = [
    ("sleepInBed", [0]),
    ("sleepAsleep", asleepValues),
    ("sleepAwake", [2]),
    ("sleepCore", [3]),
    ("sleepDeep", [4]),
    ("sleepREM", [5]),
  ]

  // Sleep samples less than this far apart belong to one sleep. A gap this
  // short with nothing recorded is a sleep the sources missed a piece of, not
  // a nap.
  static let sessionGap: TimeInterval = 30 * 60

  static func day(_ value: Any?, _ calendar: Calendar) -> Date? {
    guard let parts = (value as? String)?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else {
      return nil
    }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }

  static func key(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  static func adding(days: Int, to date: Date, _ calendar: Calendar) -> Date {
    calendar.date(byAdding: .day, value: days, to: date) ?? date
  }

  // Wall-clock noon on the day before, so a DST change does not move it.
  static func noon(before day: Date, _ calendar: Calendar) -> Date {
    let previous = adding(days: -1, to: day, calendar)
    return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: previous) ?? previous
  }

  // A night runs from noon to noon and belongs to the day it ends on.
  static func nightOf(_ end: Date, _ calendar: Calendar) -> Date {
    let day = calendar.startOfDay(for: end)
    let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: end) ?? day
    return end <= noon ? day : adding(days: 1, to: day, calendar)
  }

  // The night a noon-to-noon statistics bucket starting at bucketStart counts towards.
  static func nightKey(bucketStart: Date, _ calendar: Calendar) -> String {
    key(adding(days: 1, to: calendar.startOfDay(for: bucketStart), calendar), calendar)
  }

  // Samples are fetched a day beyond the nights asked for on each side, so a
  // sleep that crosses a range bound arrives whole.
  static func sleepFetchWindow(start: Date, end: Date, _ calendar: Calendar) -> (Date, Date) {
    (
      adding(days: -1, to: noon(before: start, calendar), calendar),
      adding(days: 1, to: noon(before: end, calendar), calendar)
    )
  }

  // Every value, in bed and awake included, joins the sleep it touches.
  static func sessions(_ samples: [SleepSample]) -> [[SleepSample]] {
    var result: [[SleepSample]] = []
    var current: [SleepSample] = []
    var currentEnd = Date.distantPast
    for sample in samples.sorted(by: { $0.start < $1.start }) {
      if !current.isEmpty, sample.start.timeIntervalSince(currentEnd) >= sessionGap {
        result.append(current)
        current = []
      }
      currentEnd = current.isEmpty ? sample.end : max(currentEnd, sample.end)
      current.append(sample)
    }
    if !current.isEmpty { result.append(current) }
    return result
  }

  // Each whole sleep goes to the night of its last end, so one that crosses
  // noon is not split. Keys are "yyyy-MM-dd"; nights outside [start, end) and
  // nights with no samples have no entry.
  static func nights(_ samples: [SleepSample], start: Date, end: Date, _ calendar: Calendar) -> [String: [SleepSample]] {
    var byNight: [String: [SleepSample]] = [:]
    for session in sessions(samples) {
      guard let last = session.map(\.end).max() else { continue }
      let night = nightOf(last, calendar)
      guard night >= start, night < end else { continue }
      byNight[key(night, calendar), default: []].append(contentsOf: session)
    }
    return byNight
  }

  // Each row is ["date": "yyyy-MM-dd", "metric": id, "value": minutes]. A
  // night with no samples of a metric has no row for it.
  static func sleepRows(
    _ samples: [SleepSample], metrics: [(id: String, values: Set<Int>)], start: Date, end: Date,
    _ calendar: Calendar
  ) -> [[String: Any]] {
    let byNight = nights(samples, start: start, end: end, calendar)
    var rows: [[String: Any]] = []
    for night in byNight.keys.sorted() {
      let samples = byNight[night] ?? []
      for metric in metrics {
        let intervals = samples.filter { metric.values.contains($0.value) }.map { ($0.start, $0.end) }
        guard !intervals.isEmpty else { continue }
        rows.append(["date": night, "metric": metric.id, "value": mergedMinutes(intervals)])
      }
    }
    return rows
  }

  // Overlapping intervals, as a Watch's and a phone's are, become one.
  static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
    var result: [(Date, Date)] = []
    for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
      if let c = result.last, interval.0 <= c.1 {
        result[result.count - 1] = (c.0, max(c.1, interval.1))
      } else {
        result.append(interval)
      }
    }
    return result
  }

  static func mergedMinutes(_ intervals: [(Date, Date)]) -> Double {
    merged(intervals).reduce(0) { $0 + $1.1.timeIntervalSince($1.0) } / 60
  }

  // Each night's asleep time (no in bed, no awake), merged across sources.
  static func asleepIntervals(_ byNight: [String: [SleepSample]]) -> [String: [(Date, Date)]] {
    var result: [String: [(Date, Date)]] = [:]
    for (night, samples) in byNight {
      let asleep = merged(samples.filter { asleepValues.contains($0.value) }.map { ($0.start, $0.end) })
      if !asleep.isEmpty { result[night] = asleep }
    }
    return result
  }

  // A sample is inside an interval [s, e) when its midpoint is, so an
  // instant sample (start == end) counts by its moment and one with a
  // duration is counted once, by where most of it falls.
  static func midpoint(_ sample: QuantitySample) -> Date {
    sample.start.addingTimeInterval(sample.end.timeIntervalSince(sample.start) / 2)
  }

  // Each row is ["date": night, "metric": metric, "value": mean], the plain
  // mean of the samples inside that night's asleep intervals. A night with
  // no asleep time, or no sample inside it, has no row.
  static func meanInsideRows(
    _ samples: [QuantitySample], asleep: [String: [(Date, Date)]], metric: String
  ) -> [[String: Any]] {
    let intervals = asleep.flatMap { night, spans in spans.map { (night: night, start: $0.0, end: $0.1) } }
      .sorted { $0.start < $1.start }
    let moments = samples.map { (at: midpoint($0), value: $0.value) }.sorted { $0.at < $1.at }
    var sums: [String: (total: Double, count: Int)] = [:]
    var i = 0
    for interval in intervals {
      while i < moments.count, moments[i].at < interval.start { i += 1 }
      var j = i
      while j < moments.count, moments[j].at < interval.end {
        let s = sums[interval.night] ?? (0, 0)
        sums[interval.night] = (s.total + moments[j].value, s.count + 1)
        j += 1
      }
      i = j
    }
    return sums.keys.sorted().map { ["date": $0, "metric": metric, "value": sums[$0]!.total / Double(sums[$0]!.count)] }
  }

  // The span from each night's first asleep moment to its last, which is all
  // the heart rate a night's mean can use.
  static func spans(_ asleep: [String: [(Date, Date)]]) -> [(Date, Date)] {
    asleep.values.compactMap { spans in
      guard let first = spans.first, let last = spans.last else { return nil }
      return (first.0, last.1)
    }.sorted { $0.0 < $1.0 }
  }

  // Sample times cross the channel as whole microseconds since 1970, so a
  // page's next start round-trips through Dart exactly.
  static func micros(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down))
  }

  static func date(micros: Int64) -> Date {
    Date(timeIntervalSince1970: Double(micros) / 1_000_000)
  }

  // samples are sorted by start and hold at most limit. A full page is cut
  // back to whole start times and next is the first start it dropped, so the
  // next page, which reads starts from next, has each tied sample once. A full
  // page that is one start time throughout is kept whole and next moves a
  // microsecond on, skipping any further samples at that start.
  static func page(_ samples: [QuantitySample], limit: Int) -> (samples: [QuantitySample], next: Int64?) {
    guard samples.count >= limit, let last = samples.last else { return (samples, nil) }
    let lastStart = micros(last.start)
    let whole = samples.prefix { micros($0.start) < lastStart }
    if whole.isEmpty { return (samples, lastStart + 1) }
    return (Array(whole), lastStart)
  }

  // [start, end, value] triples, the times in microseconds since 1970.
  static func flatten(_ samples: [QuantitySample]) -> [Double] {
    samples.flatMap { [Double(micros($0.start)), Double(micros($0.end)), $0.value] }
  }
}
