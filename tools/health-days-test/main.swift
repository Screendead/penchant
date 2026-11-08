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

if failures > 0 { exit(1) }
print("ok")
