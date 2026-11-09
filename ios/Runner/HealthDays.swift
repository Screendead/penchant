import Foundation

// The day, night and sample arithmetic behind HealthChannel.swift. It imports
// no HealthKit, so tools/health-days.test.sh can compile and test it on its own.
enum HealthDays {
  struct SleepSample {
    let start: Date
    let end: Date
    let value: Int
    // The writing source's bundle identifier. Apple's devices write as
    // com.apple.health.<device UUID>, so a Watch and its iPhone differ.
    var source = ""
    // Apple's own sleep tracking on a Watch: a productType beginning "Watch"
    // and an Apple bundle identifier. A third-party watchOS app, or a sample
    // with no productType, is not.
    var watch = false
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
  static let stageValues: Set<Int> = [3, 4, 5]
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

  // A source's span (its first to last asleep or awake moment in a sleep)
  // must take in this share of the asleep time every source recorded in that
  // sleep for it to speak for the sleep. Below it, a Watch whose battery died
  // or a staged nap would undercount a night another app recorded whole; at
  // it, a source that claims more sleep (an app counting lying in bed) still
  // loses to a source with stages that covers most of it.
  static let coverage = 0.75

  // Each sleep is found across every source, then keeps one source's samples
  // (oneSource), and goes to the night of the last end of what it kept, so
  // one that crosses noon is not split and a dropped source cannot move it.
  // Then a night whose main sleep (the most asleep time kept; a tie goes to
  // the preferred source) has samples from the preferred source, the first in
  // order and only if it writes stages, drops its sleeps in which that source
  // wrote nothing: another app's evening span on a night the Watch recorded
  // is the Watch not counting it as sleep, not a nap it missed. A night whose
  // main sleep only another app recorded keeps everything, a nap the Watch
  // caught included. Keys are "yyyy-MM-dd"; nights outside [start, end) and
  // nights with no samples have no entry.
  static func nights(_ samples: [SleepSample], start: Date, end: Date, _ calendar: Calendar) -> [String: [SleepSample]] {
    let order = preference(samples)
    let preferred = order.first.flatMap { source in
      samples.contains { $0.source == source && stageValues.contains($0.value) } ? source : nil
    }
    var byNight: [String: [(kept: [SleepSample], asleep: Double, preferred: Bool)]] = [:]
    for session in sessions(samples) {
      guard let (kept, last) = oneSource(session, order) else { continue }
      let night = nightOf(last, calendar)
      guard night >= start, night < end else { continue }
      let hasPreferred = preferred.map { source in session.contains { $0.source == source } } ?? false
      byNight[key(night, calendar), default: []].append((kept, minutes(kept, asleepValues), hasPreferred))
    }
    return byNight.mapValues { sleeps in
      let mostWith = sleeps.filter(\.preferred).map(\.asleep).max()
      let mostWithout = sleeps.filter { !$0.preferred }.map(\.asleep).max() ?? -1
      let drop = mostWith.map { $0 >= mostWithout } ?? false
      return sleeps.filter { $0.preferred || !drop }.flatMap(\.kept)
    }
  }

  static func minutes(_ samples: [SleepSample], _ values: Set<Int>) -> Double {
    mergedMinutes(samples.filter { values.contains($0.value) }.map { ($0.start, $0.end) })
  }

  // One order over every source in the read, so neighbouring nights prefer
  // the same source: sources that write stages, a Watch first, then the most
  // staged time, the most asleep time, and the bundle identifier, which makes
  // the order total.
  static func preference(_ samples: [SleepSample]) -> [String] {
    Dictionary(grouping: samples, by: \.source).map { source, samples in
      (
        source: source, staged: minutes(samples, stageValues), asleep: minutes(samples, asleepValues),
        watch: samples.contains { $0.watch }
      )
    }.sorted { a, b in
      if (a.staged > 0) != (b.staged > 0) { return a.staged > 0 }
      if a.watch != b.watch { return a.watch }
      if a.staged != b.staged { return a.staged > b.staged }
      if a.asleep != b.asleep { return a.asleep > b.asleep }
      return a.source < b.source
    }.map(\.source)
  }

  // Sources disagree: another app's one asleep span over the whole night
  // would cover the Watch's awake periods if the two were merged. So a
  // sleep's asleep, stages and awake come from one source: the first in
  // order that covers the sleep (coverage), else the one with the most asleep
  // time in it. In bed comes from that source when it has any, else from the
  // source with the most, since a Watch's stages and the iPhone's bedtime
  // schedule are separate sources. last is the latest end of the chosen
  // source's samples (of the in-bed samples when nobody recorded asleep or
  // awake); nil for an empty session.
  static func oneSource(_ session: [SleepSample], _ order: [String]) -> (kept: [SleepSample], last: Date)? {
    let bySource = Dictionary(grouping: session, by: \.source)
    let ranked = order.filter { bySource[$0] != nil }
    let asleep = merged(session.filter { asleepValues.contains($0.value) }.map { ($0.start, $0.end) })
    let total = asleep.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
    func covered(_ source: String) -> Double {
      let own = (bySource[source] ?? []).filter { $0.value != 0 }
      guard let from = own.map(\.start).min(), let to = own.map(\.end).max() else { return 0 }
      return asleep.reduce(0) { $0 + max(0, min($1.1, to).timeIntervalSince(max($1.0, from))) }
    }
    func most(_ values: Set<Int>, among sources: [String]) -> String? {
      var best: (source: String, minutes: Double)?
      for source in sources {
        let m = minutes(bySource[source] ?? [], values)
        if m > 0, m > (best?.minutes ?? 0) { best = (source, m) }
      }
      return best?.source
    }
    let writesAsleep = ranked.filter { most(asleepValues, among: [$0]) != nil }
    let chosen =
      writesAsleep.first { covered($0) >= coverage * total } ?? most(asleepValues, among: writesAsleep)
      ?? ranked.first { source in bySource[source]!.contains { $0.value != 0 } }
    let own = chosen.map { bySource[$0]! } ?? []
    let ownBed = own.contains { $0.value == 0 }
    let bed = ownBed ? [] : (most([0], among: ranked).map { bySource[$0]!.filter { $0.value == 0 } } ?? [])
    guard let last = (own.isEmpty ? bed : own).map(\.end).max() else { return nil }
    return (own + bed, last)
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

  // Overlapping intervals, as one source's stages and awake can be, become one.
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

  // Each night's asleep time (no in bed, no awake), from the night's one source.
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

  // The earliest date whose micros is at least m. date(micros: m) is not it:
  // for about one sub-second date in ten it lands later than a date that
  // micros maps to m, and a predicate from it would miss that sample. micros
  // never falls as the date moves later, so startDate >= firstDate(micros: m)
  // holds exactly when micros(startDate) >= m.
  static func firstDate(micros m: Int64) -> Date {
    var t = date(micros: m).timeIntervalSinceReferenceDate
    while micros(Date(timeIntervalSinceReferenceDate: t)) < m { t = t.nextUp }
    while micros(Date(timeIntervalSinceReferenceDate: t.nextDown)) >= m { t = t.nextDown }
    return Date(timeIntervalSinceReferenceDate: t)
  }

  // A page's query: start in [lower, upper), the same set as from <=
  // micros(start) < to.
  static func queryBounds(from: Int64, to: Int64) -> (lower: Date, upper: Date) {
    (firstDate(micros: from), firstDate(micros: to))
  }

  // read is what HealthKit answered for queryBounds(from, to) with limit,
  // sorted by start; it was full when it holds limit. Anything outside [from,
  // to) in micros is dropped. A full page is cut back to whole start times
  // and next is the first start it dropped, so the next page, which reads
  // starts from next, has each tied sample once. A full page that is one
  // start time throughout is kept whole and next moves a microsecond on,
  // skipping any further samples at that start. nil when a full answer held
  // nothing inside the bounds, which queryBounds rules out, so the caller
  // fails the read rather than end the paging early.
  static func page(_ read: [QuantitySample], from: Int64, to: Int64, limit: Int)
    -> (samples: [QuantitySample], next: Int64?)?
  {
    let samples = read.filter { micros($0.start) >= from && micros($0.start) < to }
    guard read.count >= limit else { return (samples, nil) }
    guard let last = samples.last else { return nil }
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
