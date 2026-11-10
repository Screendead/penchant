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
  // When the night's main sleep began and ended (sleepTimingRows).
  static let sleepTimingMetrics: Set<String> = ["sleepOnset", "sleepEnd"]

  // Sleep samples less than this far apart belong to one sleep. A gap this
  // short with nothing recorded is a sleep the sources missed a piece of, not
  // a nap.
  static let sessionGap: TimeInterval = 30 * 60

  // A night's sleeps less than this far apart are one night's sleep for its
  // onset and end: a night broken by an hour awake, or by a Watch taken off,
  // still began when the first part did. An evening nap ends further from
  // bedtime than this.
  static let nightGap: TimeInterval = 60 * 60

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
  // Then a night whose main sleep (the most asleep time kept; a tie goes to a
  // sleep with a Watch sample) has a Watch sample drops the sleeps before it
  // that have none. Sleeps after it stay: the rest of a night the Watch
  // stopped recording. Keys are "yyyy-MM-dd"; nights outside [start, end) and
  // nights with no samples have no entry.
  static func nights(_ samples: [SleepSample], start: Date, end: Date, _ calendar: Calendar) -> [String: [SleepSample]] {
    nightSleeps(samples, start: start, end: end, calendar).mapValues { $0.sleeps.flatMap(\.kept) }
  }

  typealias Sleep = (kept: [SleepSample], asleep: Double, inBed: Double, watch: Bool, start: Date, end: Date)

  // nights, with each night's sleeps apart and its main sleep named.
  static func nightSleeps(_ samples: [SleepSample], start: Date, end: Date, _ calendar: Calendar)
    -> [String: (sleeps: [Sleep], main: Sleep)]
  {
    let order = preference(samples)
    var byNight: [String: [Sleep]] = [:]
    for session in sessions(samples) {
      guard let (kept, last) = oneSource(session, order), let first = session.first else { continue }
      let night = nightOf(last, calendar)
      guard night >= start, night < end else { continue }
      let watch = session.contains { $0.watch }
      byNight[key(night, calendar), default: []].append(
        (kept, minutes(kept, asleepValues), minutes(kept, [0]), watch, first.start, last))
    }
    // With no asleep time anywhere (an iPhone's bedtime schedule alone), the
    // most time in bed names the main sleep, so an in-bed nap is not it.
    return byNight.mapValues { sleeps in
      let main = sleeps.max { a, b in
        if a.asleep != b.asleep { return a.asleep < b.asleep }
        if a.watch != b.watch { return b.watch }
        return a.inBed < b.inBed
      }!
      guard main.watch else { return (sleeps, main) }
      return (sleeps.filter { $0.watch || $0.start > main.start }, main)
    }
  }

  // Each row is ["date": night, "metric": "sleepOnset" or "sleepEnd",
  // "value": minutes]: the first and last asleep moment (in bed, when none
  // is asleep) of the night's main sleep and the sleeps joined to it less
  // than nightGap apart, so a nap moves neither and a broken night keeps its
  // first part. The value is clock minutes after the last noon before the
  // sleep began, so onset is in 0 to 1440 even for a sleep that ends after
  // noon and so counts for the next night, and it runs on across midnight
  // (23:00 is 660, 01:00 is 780) with no DST change in the night moving it,
  // as with a habit's time of use. End counts from the same noon.
  static func sleepTimingRows(
    _ samples: [SleepSample], metrics: Set<String>, start: Date, end: Date, _ calendar: Calendar
  ) -> [[String: Any]] {
    let byNight = nightSleeps(samples, start: start, end: end, calendar)
    var rows: [[String: Any]] = []
    for night in byNight.keys.sorted() {
      let (sleeps, main) = byNight[night]!
      let ordered = sleeps.sorted { $0.start < $1.start }
      guard let at = ordered.firstIndex(where: { $0.start == main.start && $0.end == main.end }) else { continue }
      var from = at
      var to = at
      while from > 0, ordered[from].start.timeIntervalSince(ordered[from - 1].end) < nightGap { from -= 1 }
      while to < ordered.count - 1, ordered[to + 1].start.timeIntervalSince(ordered[to].end) < nightGap { to += 1 }
      let kept = ordered[from...to].flatMap(\.kept)
      let asleep = kept.filter { asleepValues.contains($0.value) }
      let span = asleep.isEmpty ? kept.filter { $0.value == 0 } : asleep
      guard let first = span.map(\.start).min(), let last = span.map(\.end).max() else { continue }
      let opens = noon(before: nightOf(first, calendar), calendar)
      for (id, at) in [("sleepOnset", first), ("sleepEnd", last)] where metrics.contains(id) {
        rows.append(["date": night, "metric": id, "value": clockMinutes(at, after: opens, calendar)])
      }
    }
    return rows
  }

  // Wall-clock minutes from noon to date, counting whole calendar days from
  // noon's day, so it ignores a DST change between them.
  static func clockMinutes(_ date: Date, after noon: Date, _ calendar: Calendar) -> Double {
    let days =
      calendar.dateComponents([.day], from: calendar.startOfDay(for: noon), to: calendar.startOfDay(for: date)).day ?? 0
    let c = calendar.dateComponents([.hour, .minute, .second], from: date)
    // In one expression, CI's Swift compiler gives up type-checking it.
    let hour: Int = c.hour ?? 0
    let minute: Int = c.minute ?? 0
    let second: Int = c.second ?? 0
    let whole: Int = days * 24 * 60 + (hour - 12) * 60 + minute
    return Double(whole) + Double(second) / 60
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

  // Every night's time in bed, asleep or awake, from the night's one source,
  // merged across nights and naps: when the person was not up and about.
  static func bedSpans(_ byNight: [String: [SleepSample]]) -> [(Date, Date)] {
    merged(byNight.values.flatMap { $0.map { ($0.start, $0.end) } })
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

  // The day keys a sample from start to end can change: every day it touches,
  // and the day after each, since a noon-to-noon night or a sleep that crosses
  // noon counts towards the next day. Marking too many costs a reread of a day;
  // too few would leave a stale value.
  static func touchedKeys(start: Date, end: Date, _ calendar: Calendar) -> [String] {
    var keys: [String] = []
    var day = calendar.startOfDay(for: start)
    let last = adding(days: 1, to: calendar.startOfDay(for: max(start, end)), calendar)
    while day <= last {
      keys.append(key(day, calendar))
      day = adding(days: 1, to: day, calendar)
    }
    return keys
  }

  // What HealthSync keeps between launches: each sample type's anchor, and
  // the days of each metric changed since Dart last took them. A change
  // carries the generation it was marked in, so Dart's acknowledgement of
  // what it read clears nothing marked after the read began.
  struct SyncState: Codable, Equatable {
    var anchors: [String: Data] = [:]
    // The metrics Dart last asked about, which the observers watch.
    var metrics: [String] = []
    var generation = 0
    // Metric to day key to generation.
    var days: [String: [String: Int]] = [:]
    // Metrics to read whole (no anchor yet, or a deletion, whose day HealthKit
    // does not say), to generation.
    var whole: [String: Int] = [:]

    mutating func mark(_ metrics: [String], keys: [String]) {
      generation += 1
      for metric in metrics {
        if whole[metric] != nil {
          whole[metric] = generation
        } else {
          for key in keys { days[metric, default: [:]][key] = generation }
        }
      }
    }

    mutating func markWhole(_ metrics: [String]) {
      generation += 1
      for metric in metrics {
        whole[metric] = generation
        days[metric] = nil
      }
    }

    // A metric marked whole stays whole until handled; a day mark under it
    // moves its generation on instead, so a read begun before that mark does
    // not clear it.
    func pending(_ wanted: [String]) -> (days: [String: [String]], whole: [String]) {
      var out: [String: [String]] = [:]
      for metric in wanted where whole[metric] == nil {
        if let marked = days[metric], !marked.isEmpty { out[metric] = marked.keys.sorted() }
      }
      return (out, wanted.filter { whole[$0] != nil }.sorted())
    }

    mutating func handled(through handledGeneration: Int) {
      whole = whole.filter { $0.value > handledGeneration }
      days = days.compactMapValues { marked in
        let left = marked.filter { $0.value > handledGeneration }
        return left.isEmpty ? nil : left
      }
    }
  }
}
