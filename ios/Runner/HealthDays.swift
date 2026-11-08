import Foundation

// The day and night arithmetic behind HealthChannel.swift. It imports no
// HealthKit, so tools/health-days.test.sh can compile and test it on its own.
enum HealthDays {
  struct SleepSample {
    let start: Date
    let end: Date
    let value: Int
  }

  // HKCategoryValueSleepAnalysis raw values, which are stable across releases:
  // inBed 0, asleepUnspecified (iOS 15's asleep) 1, awake 2, asleepCore 3,
  // asleepDeep 4, asleepREM 5. The named cases for 3 to 5 need iOS 16.
  static let sleepMetrics: [(id: String, values: Set<Int>)] = [
    ("sleepInBed", [0]),
    ("sleepAsleep", [1, 3, 4, 5]),
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

  // Each row is ["date": "yyyy-MM-dd", "metric": id, "value": minutes]. A
  // whole sleep goes to the night of its last end, so one that crosses noon
  // is not split. A night with no samples of a metric has no row for it.
  static func sleepRows(
    _ samples: [SleepSample], metrics: [(id: String, values: Set<Int>)], start: Date, end: Date,
    _ calendar: Calendar
  ) -> [[String: Any]] {
    var byNight: [String: [SleepSample]] = [:]
    for session in sessions(samples) {
      guard let last = session.map(\.end).max() else { continue }
      let night = nightOf(last, calendar)
      guard night >= start, night < end else { continue }
      byNight[key(night, calendar), default: []].append(contentsOf: session)
    }
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

  // Overlapping intervals, as a Watch's and a phone's are, count once.
  static func mergedMinutes(_ intervals: [(Date, Date)]) -> Double {
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
