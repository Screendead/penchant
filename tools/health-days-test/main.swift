import Foundation

// Compiled with ios/Runner/HealthDays.swift by tools/health-days.test.sh.

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!
var failures = 0

func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
  if !ok {
    failures += 1
    print("FAIL: \(name) \(detail())")
  }
}

func sample(_ start: Date, _ end: Date, _ value: Int) -> HealthDays.SleepSample {
  HealthDays.SleepSample(start: start, end: end, value: value)
}

func values(_ rows: [[String: Any]]) -> [String: Double] {
  var out: [String: Double] = [:]
  for row in rows { out["\(row["date"]!) \(row["metric"]!)"] = row["value"] as? Double }
  return out
}

let allSleep = HealthDays.sleepMetrics

// nightOf: noon itself belongs to the night ending that day.
check("noon ends today's night", HealthDays.nightOf(at(2026, 11, 8, 12), calendar) == at(2026, 11, 8))
check("after noon is tomorrow's night", HealthDays.nightOf(at(2026, 11, 8, 12, 1), calendar) == at(2026, 11, 9))
check("before midnight is tomorrow's night", HealthDays.nightOf(at(2026, 11, 7, 23), calendar) == at(2026, 11, 8))

// noon(before:) stays at wall-clock noon across both 2026 UK changes.
for (day, label) in [(at(2026, 3, 30), "spring"), (at(2026, 10, 26), "autumn")] {
  let noon = HealthDays.noon(before: day, calendar)
  let c = calendar.dateComponents([.day, .hour, .minute], from: noon)
  check("noon before, \(label)", c.hour == 12 && c.minute == 0 && c.day == calendar.component(.day, from: day) - 1)
}

// A night key from a noon-to-noon bucket is the day the bucket ends on.
check("night bucket key", HealthDays.nightKey(bucketStart: at(2026, 11, 7, 12), calendar) == "2026-11-08")
check(
  "night bucket key across DST", HealthDays.nightKey(bucketStart: at(2026, 10, 24, 12), calendar) == "2026-10-25")

// Sleep 03:00 to 13:00 on Sun 8 Nov is one sleep, all of it the night of the 9th
// (it ends after noon), not split at noon.
do {
  let rows = values(
    HealthDays.sleepRows(
      [
        sample(at(2026, 11, 8, 3), at(2026, 11, 8, 13), 0),
        sample(at(2026, 11, 8, 3), at(2026, 11, 8, 11), 3),
        sample(at(2026, 11, 8, 11), at(2026, 11, 8, 12, 30), 5),
        sample(at(2026, 11, 8, 12, 30), at(2026, 11, 8, 13), 3),
      ], metrics: allSleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  check("late sleep stays whole", rows["2026-11-08 sleepInBed"] == nil, "\(rows)")
  check("late sleep in bed", rows["2026-11-09 sleepInBed"] == 600, "\(rows)")
  check("late sleep asleep", rows["2026-11-09 sleepAsleep"] == 600, "\(rows)")
  check("late sleep REM", rows["2026-11-09 sleepREM"] == 90, "\(rows)")
}

// Stage samples either side of midnight are one night, the day they end on.
do {
  let rows = values(
    HealthDays.sleepRows(
      [
        sample(at(2026, 11, 7, 23), at(2026, 11, 8, 0, 30), 3),
        sample(at(2026, 11, 8, 0, 30), at(2026, 11, 8, 1), 4),
        sample(at(2026, 11, 8, 1), at(2026, 11, 8, 1, 10), 2),
        sample(at(2026, 11, 8, 1, 10), at(2026, 11, 8, 7), 3),
      ], metrics: allSleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  check("midnight night asleep", rows["2026-11-08 sleepAsleep"] == 470, "\(rows)")
  check("midnight night awake", rows["2026-11-08 sleepAwake"] == 10, "\(rows)")
  check("midnight night deep", rows["2026-11-08 sleepDeep"] == 30, "\(rows)")
  check("no stage, no row", rows["2026-11-08 sleepREM"] == nil && rows["2026-11-08 sleepInBed"] == nil, "\(rows)")
  check("only one night", Set(rows.keys.map { String($0.prefix(10)) }) == ["2026-11-08"], "\(rows)")
}

// An afternoon nap, well apart from the night, counts towards the following night.
do {
  let rows = values(
    HealthDays.sleepRows(
      [
        sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1),
        sample(at(2026, 11, 8, 15), at(2026, 11, 8, 15, 40), 1),
      ], metrics: allSleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  check("nap night", rows["2026-11-08 sleepAsleep"] == 480, "\(rows)")
  check("nap goes to the next night", rows["2026-11-09 sleepAsleep"] == 40, "\(rows)")
}

// A Watch's and a phone's overlapping in-bed samples count once.
do {
  let rows = values(
    HealthDays.sleepRows(
      [
        sample(at(2026, 11, 7, 22), at(2026, 11, 8, 6), 0),
        sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 0),
      ], metrics: allSleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  check("merged in bed", rows["2026-11-08 sleepInBed"] == 540, "\(rows)")
}

// Nights outside [start, end) have no row, and sessions are grouped before the
// range filter, so one ending after the range's last noon is dropped whole.
do {
  let rows = values(
    HealthDays.sleepRows(
      [
        sample(at(2026, 11, 6, 23), at(2026, 11, 7, 7), 1),
        sample(at(2026, 11, 7, 3), at(2026, 11, 7, 13), 0),
        sample(at(2026, 11, 13, 23), at(2026, 11, 14, 7), 1),
      ], metrics: allSleep, start: at(2026, 11, 8), end: at(2026, 11, 14), calendar))
  check("before the range", rows["2026-11-07 sleepAsleep"] == nil, "\(rows)")
  check("crosses into the range whole", rows["2026-11-08 sleepInBed"] == 600, "\(rows)")
  check("crosses into the range, asleep part too", rows["2026-11-08 sleepAsleep"] == 480, "\(rows)")
  check("end is exclusive", rows["2026-11-14 sleepAsleep"] == nil, "\(rows)")
  check("no data is no rows", HealthDays.sleepRows([], metrics: allSleep, start: at(2026, 11, 8), end: at(2026, 11, 14), calendar).isEmpty)
}

// The fetch window reaches a day past each bound's noon.
do {
  let (from, to) = HealthDays.sleepFetchWindow(start: at(2026, 11, 8), end: at(2026, 11, 14), calendar)
  check("fetch from", from == at(2026, 11, 6, 12))
  check("fetch to", to == at(2026, 11, 14, 12))
}

// A gap shorter than sessionGap joins two pieces; a longer one does not.
do {
  let near = HealthDays.sessions([
    sample(at(2026, 11, 8, 3), at(2026, 11, 8, 11, 50), 1),
    sample(at(2026, 11, 8, 12, 5), at(2026, 11, 8, 13), 1),
  ])
  check("short gap is one sleep", near.count == 1)
  let far = HealthDays.sessions([
    sample(at(2026, 11, 8, 0), at(2026, 11, 8, 7), 1),
    sample(at(2026, 11, 8, 15), at(2026, 11, 8, 16), 1),
  ])
  check("long gap is two", far.count == 2)
}

check("merged minutes", HealthDays.mergedMinutes([(at(2026, 1, 1, 1), at(2026, 1, 1, 2)), (at(2026, 1, 1, 1, 30), at(2026, 1, 1, 3)), (at(2026, 1, 1, 4), at(2026, 1, 1, 4, 15))]) == 135)

func hr(_ start: Date, _ value: Double, _ seconds: TimeInterval = 0) -> HealthDays.QuantitySample {
  HealthDays.QuantitySample(start: start, end: start.addingTimeInterval(seconds), value: value)
}

func sleepingHeartRate(_ sleep: [HealthDays.SleepSample], _ heart: [HealthDays.QuantitySample]) -> [String: Double] {
  let asleep = HealthDays.asleepIntervals(HealthDays.nights(sleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  return values(HealthDays.meanInsideRows(heart, asleep: asleep, metric: "sleepingHeartRate"))
}

// Sleeping heart rate is the mean of the samples inside the night's asleep
// time: not in bed, not awake, not the evening before, and an interval's end
// is outside it.
do {
  let sleep = [
    sample(at(2026, 11, 7, 22, 30), at(2026, 11, 8, 7), 0),
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 2), 3),
    sample(at(2026, 11, 8, 2), at(2026, 11, 8, 2, 30), 2),
    sample(at(2026, 11, 8, 2, 30), at(2026, 11, 8, 6), 4),
  ]
  let rows = sleepingHeartRate(
    sleep,
    [
      hr(at(2026, 11, 7, 21), 90),
      hr(at(2026, 11, 7, 22, 45), 80),
      hr(at(2026, 11, 7, 23), 50),
      hr(at(2026, 11, 8, 1), 54),
      hr(at(2026, 11, 8, 2, 10), 75),
      hr(at(2026, 11, 8, 2), 70),
      hr(at(2026, 11, 8, 4), 52),
      hr(at(2026, 11, 8, 6), 66),
    ])
  check("sleeping heart rate mean", rows["2026-11-08 sleepingHeartRate"] == 52, "\(rows)")
  check("sleeping heart rate one night", rows.count == 1, "\(rows)")
}

// A Watch's and a phone's overlapping asleep samples count a heart rate sample once.
do {
  let rows = sleepingHeartRate(
    [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 5), 1), sample(at(2026, 11, 8, 0), at(2026, 11, 8, 6), 3)],
    [hr(at(2026, 11, 8, 1), 50), hr(at(2026, 11, 8, 5, 30), 60)])
  check("overlapping sources count once", rows["2026-11-08 sleepingHeartRate"] == 55, "\(rows)")
}

// A sample with a duration counts by its midpoint.
do {
  let rows = sleepingHeartRate(
    [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 6), 1)],
    [hr(at(2026, 11, 7, 22, 50), 70, 30 * 60), hr(at(2026, 11, 8, 5, 50), 90, 30 * 60), hr(at(2026, 11, 8, 3), 50)])
  check("midpoint inside counts", rows["2026-11-08 sleepingHeartRate"] == 60, "\(rows)")
}

// No asleep time is no value, never zero: in bed alone, or no sleep at all;
// and asleep time with no heart rate inside it is no value either.
do {
  check(
    "in bed only is no value",
    sleepingHeartRate([sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 0)], [hr(at(2026, 11, 8, 3), 50)]).isEmpty)
  check("no sleep is no value", sleepingHeartRate([], [hr(at(2026, 11, 8, 3), 50)]).isEmpty)
  check(
    "no heart rate is no value",
    sleepingHeartRate([sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1)], [hr(at(2026, 11, 8, 9), 50)]).isEmpty)
}

// Two nights and a nap: each keyed like the sleep metrics, the nap to the next night.
do {
  let sleep = [
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1),
    sample(at(2026, 11, 8, 15), at(2026, 11, 8, 16), 1),
    sample(at(2026, 11, 8, 23), at(2026, 11, 9, 7), 1),
  ]
  let rows = sleepingHeartRate(
    sleep, [hr(at(2026, 11, 8, 3), 50), hr(at(2026, 11, 8, 15, 30), 70), hr(at(2026, 11, 9, 3), 60), hr(at(2026, 11, 8, 12), 99)])
  check("first night", rows["2026-11-08 sleepingHeartRate"] == 50, "\(rows)")
  check("nap joins the next night", rows["2026-11-09 sleepingHeartRate"] == 65, "\(rows)")
  let asleep = HealthDays.asleepIntervals(HealthDays.nights(sleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
  let spans = HealthDays.spans(asleep)
  check(
    "spans per night", spans.count == 2 && spans[0] == (at(2026, 11, 7, 23), at(2026, 11, 8, 7))
      && spans[1] == (at(2026, 11, 8, 15), at(2026, 11, 9, 7)), "\(spans)")
}

// Paging: a short page is the last; a full page is cut back to whole start
// times, and the next page starts at the first one it dropped.
do {
  let t = at(2026, 11, 8, 3)
  let from = HealthDays.micros(t), to = HealthDays.micros(t.addingTimeInterval(3600))
  func page(_ read: [HealthDays.QuantitySample], limit: Int) -> (samples: [HealthDays.QuantitySample], next: Int64?) {
    HealthDays.page(read, from: from, to: to, limit: limit)!
  }
  let short = page([hr(t, 1), hr(t.addingTimeInterval(60), 2)], limit: 3)
  check("short page is last", short.next == nil && short.samples.count == 2)
  let full = page(
    [hr(t, 1), hr(t.addingTimeInterval(60), 2), hr(t.addingTimeInterval(120), 3), hr(t.addingTimeInterval(120), 4)],
    limit: 4)
  check("full page drops the tied tail", full.samples.map(\.value) == [1, 2], "\(full)")
  check("next is the tied start", full.next == HealthDays.micros(t.addingTimeInterval(120)), "\(full)")
  let untied = page([hr(t, 1), hr(t.addingTimeInterval(60), 2)], limit: 2)
  check(
    "untied full page keeps all but the last start",
    untied.samples.map(\.value) == [1] && untied.next == HealthDays.micros(t.addingTimeInterval(60)))
  let stuck = page([hr(t, 1), hr(t, 2)], limit: 2)
  check("one start throughout still moves on", stuck.samples.count == 2 && stuck.next == HealthDays.micros(t) + 1)
  let outside = HealthDays.page(
    [hr(t.addingTimeInterval(-1), 1), hr(t, 2), hr(t.addingTimeInterval(3600), 3)], from: from, to: to, limit: 4)!
  check("outside the bounds is dropped", outside.samples.map(\.value) == [2] && outside.next == nil, "\(outside)")
  check(
    "a full answer with nothing inside fails",
    HealthDays.page([hr(t.addingTimeInterval(-1), 1)], from: from, to: to, limit: 1) == nil)
}

// firstDate(micros: m) is the earliest date that micros maps to m or later,
// for sub-second, whole-millisecond and whole-second dates. A Date holds
// seconds since 2001, as HealthKit's are built.
let base = at(2026, 1, 1).timeIntervalSinceReferenceDate
func randomDates(_ n: Int, step: Double) -> [Date] {
  (0..<n).map { _ in
    let raw = base + Double.random(in: 0..<(366 * 86_400))
    return Date(timeIntervalSinceReferenceDate: step == 0 ? raw : (raw / step).rounded(.down) * step)
  }
}
let subSecond = randomDates(20_000, step: 0), wholeMilli = randomDates(20_000, step: 0.001)
do {
  var bad = 0, wobbly = 0
  for t in subSecond + wholeMilli + randomDates(2_000, step: 1) {
    let m = HealthDays.micros(t)
    if HealthDays.date(micros: m) > t { wobbly += 1 }
    let first = HealthDays.firstDate(micros: m)
    let below = Date(timeIntervalSinceReferenceDate: first.timeIntervalSinceReferenceDate.nextDown)
    if !(first <= t && HealthDays.micros(first) >= m && HealthDays.micros(below) < m) { bad += 1 }
  }
  check("firstDate is the earliest date of its microsecond", bad == 0, "\(bad) wrong")
  check("the dates include ones date(micros:) puts later", wobbly > 0)
}

// Whole paging runs, each page answered as HealthKit would answer its
// predicate: every sample is read once, ties at page boundaries included.
func pageThrough(_ all: [HealthDays.QuantitySample], from: Int64, to: Int64, limit: Int) -> [Double]? {
  var read: [Double] = []
  var next: Int64? = from
  var calls = 0
  while let cursor = next, cursor < to {
    calls += 1
    if calls > all.count + 10 { return nil }
    let bounds = HealthDays.queryBounds(from: cursor, to: to)
    let answer = Array(all.filter { $0.start >= bounds.lower && $0.start < bounds.upper }.prefix(limit))
    guard let page = HealthDays.page(answer, from: cursor, to: to, limit: limit) else { return nil }
    read += page.samples.map(\.value)
    next = page.next
  }
  return read
}
for (dates, label) in [(subSecond, "sub-second"), (wholeMilli, "whole-millisecond")] {
  // Starts that date(micros:) moves later, each tied with a second source's
  // sample, so pages keep ending on them.
  let tricky = dates.filter { HealthDays.date(micros: HealthDays.micros($0)) > $0 }.prefix(300).sorted()
  var all: [HealthDays.QuantitySample] = []
  for (i, t) in tricky.enumerated() {
    all.append(HealthDays.QuantitySample(start: t, end: t, value: Double(2 * i)))
    all.append(HealthDays.QuantitySample(start: t, end: t, value: Double(2 * i + 1)))
  }
  let from = HealthDays.micros(tricky.first!), to = HealthDays.micros(tricky.last!) + 1
  for limit in [3, 4, 7] {
    let read = pageThrough(all, from: from, to: to, limit: limit)
    check("\(label) pages of \(limit) read every sample once", read?.sorted() == all.map(\.value), "\(read?.count ?? -1)")
  }
  // Windows that end on a tricky start: the sample there is in the next window.
  let mid = HealthDays.micros(tricky[tricky.count / 2])
  let halves = (pageThrough(all, from: from, to: mid, limit: 5) ?? []) + (pageThrough(all, from: mid, to: to, limit: 5) ?? [])
  check("\(label) adjacent windows split each sample once", halves.sorted() == all.map(\.value), "\(halves.count)")
}

// flatten writes start, end, value triples.
check(
  "flatten", HealthDays.flatten([hr(at(2026, 11, 8), 61.5, 1)]) == [
    Double(HealthDays.micros(at(2026, 11, 8))), Double(HealthDays.micros(at(2026, 11, 8))) + 1_000_000, 61.5,
  ])

if failures > 0 { exit(1) }
print("ok")
