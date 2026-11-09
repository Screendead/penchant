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
  let short = HealthDays.page([hr(t, 1), hr(t.addingTimeInterval(60), 2)], limit: 3)
  check("short page is last", short.next == nil && short.samples.count == 2)
  let full = HealthDays.page(
    [hr(t, 1), hr(t.addingTimeInterval(60), 2), hr(t.addingTimeInterval(120), 3), hr(t.addingTimeInterval(120), 4)],
    limit: 4)
  check("full page drops the tied tail", full.samples.map(\.value) == [1, 2], "\(full)")
  check("next is the tied start", full.next == HealthDays.micros(t.addingTimeInterval(120)), "\(full)")
  let untied = HealthDays.page([hr(t, 1), hr(t.addingTimeInterval(60), 2)], limit: 2)
  check("untied full page keeps all but the last start", untied.samples.map(\.value) == [1] && untied.next == HealthDays.micros(t.addingTimeInterval(60)))
  let stuck = HealthDays.page([hr(t, 1), hr(t, 2)], limit: 2)
  check("one start throughout still moves on", stuck.samples.count == 2 && stuck.next == HealthDays.micros(t) + 1)
}

// Microseconds round-trip, and flatten writes start, end, value triples.
do {
  let t = Date(timeIntervalSince1970: 1_794_000_000.123456)
  check("micros round-trip", HealthDays.micros(HealthDays.date(micros: HealthDays.micros(t))) == HealthDays.micros(t))
  check(
    "flatten", HealthDays.flatten([hr(at(2026, 11, 8), 61.5, 1)]) == [
      Double(HealthDays.micros(at(2026, 11, 8))), Double(HealthDays.micros(at(2026, 11, 8))) + 1_000_000, 61.5,
    ])
}

if failures > 0 { exit(1) }
print("ok")
