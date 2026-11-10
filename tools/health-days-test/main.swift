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

// One source's overlapping in-bed samples count once.
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

// Sources are not merged for sleep. The Watch's core 23:00-03:00, awake
// 03:00-04:00, core 04:00-07:00 beside another app's asleep 23:00-07:00 is
// the Watch's night alone, not 480 asleep with 60 awake.
func from(_ source: String, watch: Bool = false, _ samples: [HealthDays.SleepSample]) -> [HealthDays.SleepSample] {
  samples.map { HealthDays.SleepSample(start: $0.start, end: $0.end, value: $0.value, source: source, watch: watch) }
}
let watchNight = from(
  "com.apple.health.watch", watch: true,
  [
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 3), 3),
    sample(at(2026, 11, 8, 3), at(2026, 11, 8, 4), 2),
    sample(at(2026, 11, 8, 4), at(2026, 11, 8, 7), 3),
  ])
let otherAppNight = from("com.example.sleepapp", [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1)])
func sleepValues(_ samples: [HealthDays.SleepSample]) -> [String: Double] {
  values(HealthDays.sleepRows(samples, metrics: allSleep, start: at(2026, 11, 1), end: at(2026, 11, 15), calendar))
}
do {
  let alone = sleepValues(watchNight)
  check("watch alone asleep", alone["2026-11-08 sleepAsleep"] == 420, "\(alone)")
  for order in [watchNight + otherAppNight, otherAppNight + watchNight] {
    let rows = sleepValues(order)
    check("other app does not cover awake, asleep", rows["2026-11-08 sleepAsleep"] == 420, "\(rows)")
    check("other app does not cover awake, awake", rows["2026-11-08 sleepAwake"] == 60, "\(rows)")
    check("other app does not cover awake, core", rows["2026-11-08 sleepCore"] == 420, "\(rows)")
  }
}

// A night from another app alone still counts.
do {
  let rows = sleepValues(otherAppNight)
  check("other app alone", rows["2026-11-08 sleepAsleep"] == 480 && rows["2026-11-08 sleepAwake"] == nil, "\(rows)")
}

// Two sources writing stages: the sleep is one of them whole, the Watch
// whenever it covers the sleep, even with less staged time.
do {
  let ring = from(
    "com.example.ring",
    [
      sample(at(2026, 11, 7, 22), at(2026, 11, 8, 2), 4),
      sample(at(2026, 11, 8, 2), at(2026, 11, 8, 6), 5),
    ])
  for order in [watchNight + ring, ring + watchNight] {
    let rows = sleepValues(order)
    check("the Watch over more staged time", rows["2026-11-08 sleepAsleep"] == 420 && rows["2026-11-08 sleepCore"] == 420, "\(rows)")
    check("the Watch over more staged time, whole", rows["2026-11-08 sleepDeep"] == nil && rows["2026-11-08 sleepREM"] == nil, "\(rows)")
  }
}

// Two staged sources and no Watch, with the same staged and asleep time over
// the same span: the bundle identifier decides, so the pick is not left to
// dictionary order.
do {
  let deep = from("com.example.b", [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 4)])
  let rem = from("com.example.a", [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 5)])
  for order in [deep + rem, rem + deep] {
    let rows = sleepValues(order)
    check("tie, by bundle identifier", rows["2026-11-08 sleepREM"] == 480 && rows["2026-11-08 sleepDeep"] == nil, "\(rows)")
  }
}

// Two staged sources and no Watch over two nights: each night comes from the
// source with the most staged time over the whole read, not from whichever
// has more that night.
do {
  let a = from(
    "com.example.a",
    [
      sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 4),
      sample(at(2026, 11, 8, 23), at(2026, 11, 9, 6, 50), 4),
    ])
  let b = from(
    "com.example.b",
    [
      sample(at(2026, 11, 7, 23), at(2026, 11, 8, 5), 5),
      sample(at(2026, 11, 8, 23), at(2026, 11, 9, 7), 5),
    ])
  let rows = sleepValues(a + b)
  check("one source across nights, first", rows["2026-11-08 sleepDeep"] == 480 && rows["2026-11-08 sleepREM"] == nil, "\(rows)")
  check("one source across nights, second", rows["2026-11-09 sleepDeep"] == 470 && rows["2026-11-09 sleepREM"] == nil, "\(rows)")
}

// Stages lose when their source does not cover the sleep: its span must take
// in three quarters of the asleep time every source recorded.
do {
  func night(_ watchEnd: Date, _ other: [HealthDays.SleepSample]) -> [String: Double] {
    sleepValues(from("com.apple.health.watch", watch: true, [sample(at(2026, 11, 7, 23), watchEnd, 3)]) + other)
  }
  let died = night(at(2026, 11, 8, 1), otherAppNight)
  check("a Watch that died at 01:00", died["2026-11-08 sleepAsleep"] == 480 && died["2026-11-08 sleepCore"] == nil, "\(died)")
  let half = night(at(2026, 11, 8, 4), otherAppNight)
  check("a Watch that died at 04:00", half["2026-11-08 sleepAsleep"] == 480 && half["2026-11-08 sleepCore"] == nil, "\(half)")
  let most = night(at(2026, 11, 8, 6), otherAppNight)
  check("a Watch that stopped at 06:00", most["2026-11-08 sleepAsleep"] == 420 && most["2026-11-08 sleepCore"] == 420, "\(most)")
  let longer = sleepValues(watchNight + from("com.example.sleepapp", [sample(at(2026, 11, 7, 22), at(2026, 11, 8, 8), 1)]))
  check("stages beat a longer span", longer["2026-11-08 sleepAsleep"] == 420 && longer["2026-11-08 sleepAwake"] == 60, "\(longer)")
  let muchLonger = sleepValues(watchNight + from("com.example.sleepapp", [sample(at(2026, 11, 7, 21), at(2026, 11, 8, 9), 1)]))
  check("a span half as long again beats stages", muchLonger["2026-11-08 sleepAsleep"] == 720 && muchLonger["2026-11-08 sleepCore"] == nil, "\(muchLonger)")
}

// The choice is per sleep: a staged nap the afternoon before and another
// app's night that follows it are separate sleeps of the same night.
do {
  let nap = from("com.apple.health.watch", watch: true, [sample(at(2026, 11, 7, 14), at(2026, 11, 7, 14, 40), 3)])
  let rows = sleepValues(nap + otherAppNight)
  check("staged nap and another app's night", rows["2026-11-08 sleepAsleep"] == 520 && rows["2026-11-08 sleepCore"] == 40, "\(rows)")
}

// Another app's sleep that has no Watch sample, before a night's main sleep
// that has one, is dropped. Watch core 00:00-03:00, awake 03:00-04:00, deep 04:00-08:00 on
// 2 March; the app's asleep 17:00-19:00 the evening before.
func march(_ samples: [HealthDays.SleepSample]) -> [String: Double] {
  values(HealthDays.sleepRows(samples, metrics: allSleep, start: at(2026, 3, 1), end: at(2026, 3, 8), calendar))
}
let marchWatch = from(
  "com.apple.health.watch", watch: true,
  [
    sample(at(2026, 3, 2, 0), at(2026, 3, 2, 3), 3),
    sample(at(2026, 3, 2, 3), at(2026, 3, 2, 4), 2),
    sample(at(2026, 3, 2, 4), at(2026, 3, 2, 8), 4),
  ])
let appEvening = from("com.example.sleepapp", [sample(at(2026, 3, 1, 17), at(2026, 3, 1, 19), 1)])
do {
  check("evening repro, Watch alone", march(marchWatch)["2026-03-02 sleepAsleep"] == 420)
  for order in [marchWatch + appEvening, appEvening + marchWatch] {
    let rows = march(order)
    check("evening repro, with the app", rows["2026-03-02 sleepAsleep"] == 420 && rows["2026-03-02 sleepAwake"] == 60, "\(rows)")
    check("evening repro, stages", rows["2026-03-02 sleepCore"] == 180 && rows["2026-03-02 sleepDeep"] == 240, "\(rows)")
    check("evening repro, one night", Set(rows.keys.map { String($0.prefix(10)) }) == ["2026-03-02"], "\(rows)")
  }
  let asleep = HealthDays.asleepIntervals(
    HealthDays.nights(marchWatch + appEvening, start: at(2026, 3, 1), end: at(2026, 3, 8), calendar))
  let heart = values(
    HealthDays.meanInsideRows([hr(at(2026, 3, 1, 18), 90), hr(at(2026, 3, 2, 1), 50)], asleep: asleep, metric: "hr"))
  check("evening repro, heart rate", heart["2026-03-02 hr"] == 50, "\(heart)")
}

// The Watch dies at 01:00 and the app covers 23:00-07:00: the app's night
// still counts, being one sleep with the Watch's piece in it, and the evening
// span before it is dropped.
do {
  let died = from("com.apple.health.watch", watch: true, [sample(at(2026, 3, 1, 23), at(2026, 3, 2, 1), 3)])
  let appNight = from("com.example.sleepapp", [sample(at(2026, 3, 1, 23), at(2026, 3, 2, 7), 1)])
  for order in [died + appNight, appNight + died] {
    let rows = march(order)
    check("Watch died, app night", rows["2026-03-02 sleepAsleep"] == 480 && rows["2026-03-02 sleepCore"] == nil, "\(rows)")
  }
  for order in [died + appNight + appEvening, appEvening + appNight + died] {
    let rows = march(order)
    check("Watch died, evening dropped", rows["2026-03-02 sleepAsleep"] == 480, "\(rows)")
  }
}

// A night only the app recorded, evening and nap included, counts whole,
// though the Watch recorded the night before.
do {
  let appOnly = from(
    "com.example.sleepapp",
    [
      sample(at(2026, 3, 2, 15), at(2026, 3, 2, 15, 40), 1),
      sample(at(2026, 3, 2, 23), at(2026, 3, 3, 7), 1),
    ])
  let appNight = from("com.example.sleepapp", [sample(at(2026, 3, 1, 23), at(2026, 3, 2, 7), 1)])
  check("app alone, evening and night", march(appEvening + appNight)["2026-03-02 sleepAsleep"] == 600)
  for order in [marchWatch + appOnly, appOnly + marchWatch] {
    let rows = march(order)
    check("app-only nap, no Watch that night", rows["2026-03-03 sleepAsleep"] == 520, "\(rows)")
    check("app-only nap, the Watch's night", rows["2026-03-02 sleepAsleep"] == 420, "\(rows)")
  }
}

// The Watch records 23:00-04:00 and dies; the app's asleep 23:00-04:30 is the
// same sleep, and its 05:15-07:00 after the gap is a sleep of its own, after
// the main one, so it counts.
do {
  let watch = from("com.apple.health.watch", watch: true, [sample(at(2026, 3, 1, 23), at(2026, 3, 2, 4), 3)])
  let app = from(
    "com.example.sleepapp",
    [
      sample(at(2026, 3, 1, 23), at(2026, 3, 2, 4, 30), 1),
      sample(at(2026, 3, 2, 5, 15), at(2026, 3, 2, 7), 1),
    ])
  for order in [watch + app, app + watch] {
    let rows = march(order)
    check("Watch died, later app sleep", rows["2026-03-02 sleepAsleep"] == 405 && rows["2026-03-02 sleepCore"] == 300, "\(rows)")
  }
}

// The Watch records 23:00-06:00 and comes off to charge; the app's 06:45-09:00
// after it counts.
do {
  let watch = from("com.apple.health.watch", watch: true, [sample(at(2026, 3, 1, 23), at(2026, 3, 2, 6), 3)])
  let app = from("com.example.sleepapp", [sample(at(2026, 3, 2, 6, 45), at(2026, 3, 2, 9), 1)])
  for order in [watch + app, app + watch] {
    check("Watch off to charge, later app sleep", march(order)["2026-03-02 sleepAsleep"] == 555, "\(march(order))")
  }
}

// A tie for the main sleep goes to the one with a Watch sample: Watch core
// 00:00-02:00 and the app's 17:00-19:00 the evening before, 120 each.
do {
  let watch = from("com.apple.health.watch", watch: true, [sample(at(2026, 3, 2, 0), at(2026, 3, 2, 2), 3)])
  for order in [watch + appEvening, appEvening + watch] {
    let rows = march(order)
    check("tie goes to the Watch", rows["2026-03-02 sleepAsleep"] == 120 && rows["2026-03-02 sleepCore"] == 120, "\(rows)")
  }
}

// Only a Watch drops anything, whatever else the read holds: a ring's staged
// night 23:00-07:00 on 4 March keeps the app's nap 14:00-15:00 before it, with
// or without a Watch night elsewhere in the read.
do {
  let ring = from("com.example.ring", [sample(at(2026, 3, 3, 23), at(2026, 3, 4, 7), 3)])
  let nap = from("com.example.sleepapp", [sample(at(2026, 3, 3, 14), at(2026, 3, 3, 15), 1)])
  for order in [ring + nap, nap + ring, marchWatch + ring + nap, nap + ring + marchWatch] {
    let rows = march(order)
    check("ring night keeps the app's nap", rows["2026-03-04 sleepAsleep"] == 540, "\(rows)")
  }
}

// A sleep goes to the night its chosen source ends on. Another app's span to
// 12:30, joined to the Watch's night and dropped, does not move it to the next.
do {
  let rows = sleepValues(
    watchNight
      + from("com.example.sleepapp", [sample(at(2026, 11, 8, 6, 50), at(2026, 11, 8, 12, 30), 1)])
      + from("com.apple.health.watch", watch: true, [sample(at(2026, 11, 8, 23), at(2026, 11, 9, 7), 3)]))
  check("dropped span does not move the night", rows["2026-11-08 sleepAsleep"] == 420, "\(rows)")
  check("dropped span, next night alone", rows["2026-11-09 sleepAsleep"] == 480, "\(rows)")
}

// In bed comes from the chosen source when it writes any, else from the
// source with the most, so the iPhone's schedule still fills in the Watch's night.
do {
  let phone = from("com.apple.health.phone", [sample(at(2026, 11, 7, 22, 30), at(2026, 11, 8, 7, 30), 0)])
  let rows = sleepValues(watchNight + phone + otherAppNight)
  check("in bed from another source", rows["2026-11-08 sleepInBed"] == 540, "\(rows)")
  check("in bed source does not add asleep", rows["2026-11-08 sleepAsleep"] == 420, "\(rows)")
  let ownBed = watchNight + from("com.apple.health.watch", watch: true, [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 0)])
  let own = sleepValues(ownBed + phone)
  check("in bed from the chosen source first", own["2026-11-08 sleepInBed"] == 480, "\(own)")
}

// Sources mixed across midnight and noon still key the night as before:
// another app's late nap is its own session, the next night.
do {
  let nap = from("com.example.sleepapp", [sample(at(2026, 11, 8, 15), at(2026, 11, 8, 15, 40), 1)])
  let rows = sleepValues(watchNight + otherAppNight + nap)
  check("mixed sources, night", rows["2026-11-08 sleepAsleep"] == 420, "\(rows)")
  check("mixed sources, nap", rows["2026-11-09 sleepAsleep"] == 40, "\(rows)")
  check("mixed sources, two nights", Set(rows.keys.map { String($0.prefix(10)) }) == ["2026-11-08", "2026-11-09"], "\(rows)")
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

// One source's overlapping asleep samples count a heart rate sample once.
do {
  let rows = sleepingHeartRate(
    [sample(at(2026, 11, 7, 23), at(2026, 11, 8, 5), 1), sample(at(2026, 11, 8, 0), at(2026, 11, 8, 6), 3)],
    [hr(at(2026, 11, 8, 1), 50), hr(at(2026, 11, 8, 5, 30), 60)])
  check("overlapping sources count once", rows["2026-11-08 sleepingHeartRate"] == 55, "\(rows)")
}

// Sleeping heart rate uses the same source as the sleep rows: a sample in
// the Watch's awake hour is out, though another app's span covers it.
do {
  let rows = sleepingHeartRate(watchNight + otherAppNight, [hr(at(2026, 11, 8, 1), 50), hr(at(2026, 11, 8, 3, 30), 90), hr(at(2026, 11, 8, 5), 54)])
  check("sleeping heart rate skips the Watch's awake", rows["2026-11-08 sleepingHeartRate"] == 52, "\(rows)")
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

// bedSpans: in bed, asleep and awake join into one span a night; a nap is its own.
do {
  let night = [
    sample(at(2026, 3, 2, 22, 30), at(2026, 3, 2, 23, 0), 0),
    sample(at(2026, 3, 2, 23, 0), at(2026, 3, 3, 3, 0), 3),
    sample(at(2026, 3, 3, 3, 0), at(2026, 3, 3, 3, 20), 2),
    sample(at(2026, 3, 3, 3, 20), at(2026, 3, 3, 6, 40), 4),
    sample(at(2026, 3, 3, 14, 0), at(2026, 3, 3, 14, 40), 3),
  ]
  let spans = HealthDays.bedSpans(HealthDays.nights(night, start: at(2026, 3, 1), end: at(2026, 3, 8), calendar))
  check(
    "bedSpans",
    spans.map { [$0.0, $0.1] } == [
      [at(2026, 3, 2, 22, 30), at(2026, 3, 3, 6, 40)], [at(2026, 3, 3, 14, 0), at(2026, 3, 3, 14, 40)],
    ], "\(spans)")
}

// flatten writes start, end, value triples.
check(
  "flatten", HealthDays.flatten([hr(at(2026, 11, 8), 61.5, 1)]) == [
    Double(HealthDays.micros(at(2026, 11, 8))), Double(HealthDays.micros(at(2026, 11, 8))) + 1_000_000, 61.5,
  ])

// Sleep onset and end: the main sleep's first and last asleep moment, in
// clock minutes after the noon that opens the night.
func timing(_ samples: [HealthDays.SleepSample], _ metrics: Set<String> = HealthDays.sleepTimingMetrics)
  -> [String: Double]
{
  values(HealthDays.sleepTimingRows(samples, metrics: metrics, start: at(2026, 1, 1), end: at(2027, 1, 1), calendar))
}
do {
  // A nap before the night's main sleep moves neither time.
  let rows = timing([
    sample(at(2026, 11, 7, 15), at(2026, 11, 7, 15, 40), 1),
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1),
  ])
  check("onset of the main sleep", rows["2026-11-08 sleepOnset"] == 660, "\(rows)")
  check("end of the main sleep", rows["2026-11-08 sleepEnd"] == 1140, "\(rows)")
}
do {
  // Past midnight runs on from 24:00; in bed alone stands in for asleep.
  let late = timing([sample(at(2026, 11, 8, 1), at(2026, 11, 8, 8, 30), 3)])
  check("onset past midnight", late["2026-11-08 sleepOnset"] == 780, "\(late)")
  check("end past midnight", late["2026-11-08 sleepEnd"] == 1230, "\(late)")
  let bed = timing([sample(at(2026, 11, 7, 22, 30), at(2026, 11, 8, 6, 30), 0)])
  check("onset from in bed", bed["2026-11-08 sleepOnset"] == 630, "\(bed)")
  // In bed before falling asleep is not the onset.
  let both = timing([
    sample(at(2026, 11, 7, 22), at(2026, 11, 8, 7), 0),
    sample(at(2026, 11, 7, 23, 15), at(2026, 11, 8, 6, 45), 3),
  ])
  check("onset is asleep, not in bed", both["2026-11-08 sleepOnset"] == 675, "\(both)")
  let onsetOnly = timing([sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 1)], ["sleepOnset"])
  check("only the times asked for", onsetOnly.keys.sorted() == ["2026-11-08 sleepOnset"], "\(onsetOnly)")
}
do {
  // A sleep that ends after noon counts for the next night, but its onset is
  // still read from the noon before it began: 03:00 is 900, whether waking
  // at 11:30 or 12:30.
  let before = timing([sample(at(2026, 11, 8, 3), at(2026, 11, 8, 11, 30), 1)])
  check("onset, waking before noon", before["2026-11-08 sleepOnset"] == 900, "\(before)")
  let after = timing([sample(at(2026, 11, 8, 3), at(2026, 11, 8, 12, 30), 1)])
  check("onset, waking after noon", after["2026-11-09 sleepOnset"] == 900, "\(after)")
  check("end, waking after noon", after["2026-11-09 sleepEnd"] == 1470, "\(after)")
  // In bed alone (no Watch): the night, not an earlier in-bed nap of equal
  // asleep time, is the main sleep.
  let bed = timing([
    sample(at(2026, 11, 7, 15), at(2026, 11, 7, 15, 40), 0),
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 7), 0),
  ])
  check("in-bed nap is not the onset", bed["2026-11-08 sleepOnset"] == 660, "\(bed)")
  check("in-bed nap is not the end", bed["2026-11-08 sleepEnd"] == 1140, "\(bed)")
  // A night broken by 45 unrecorded minutes began with its first part, and
  // ended with its last even when that part is the shorter.
  let broken = timing([
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 1), 1),
    sample(at(2026, 11, 8, 1, 45), at(2026, 11, 8, 7), 1),
  ])
  check("broken night, onset", broken["2026-11-08 sleepOnset"] == 660, "\(broken)")
  check("broken night, end", broken["2026-11-08 sleepEnd"] == 1140, "\(broken)")
  let tail = timing([
    sample(at(2026, 11, 7, 23), at(2026, 11, 8, 5), 1),
    sample(at(2026, 11, 8, 5, 45), at(2026, 11, 8, 7), 1),
  ])
  check("broken night, short last part", tail["2026-11-08 sleepEnd"] == 1140, "\(tail)")
}
do {
  // Clock time across the 2026 UK changes: 23:00 is 660 and 07:00 is 1140.
  for (month, night, label) in [(10, 25, "autumn"), (3, 29, "spring")] {
    let rows = timing([sample(at(2026, month, night - 1, 23), at(2026, month, night, 7), 1)])
    let key = String(format: "2026-%02d-%02d", month, night)
    check("onset across DST, \(label)", rows["\(key) sleepOnset"] == 660, "\(rows)")
    check("end across DST, \(label)", rows["\(key) sleepEnd"] == 1140, "\(rows)")
  }
}

// A sample touches its days and the day after each.
check(
  "touched keys", HealthDays.touchedKeys(start: at(2026, 11, 7, 23), end: at(2026, 11, 8, 7), calendar)
    == ["2026-11-07", "2026-11-08", "2026-11-09"])
check(
  "touched keys, instant", HealthDays.touchedKeys(start: at(2026, 11, 8, 9), end: at(2026, 11, 8, 9), calendar)
    == ["2026-11-08", "2026-11-09"])

do {
  var state = HealthDays.SyncState()
  state.markWhole(["stepCount"])
  state.mark(["stepCount", "sleepAsleep"], keys: ["2026-11-08"])
  var pending = state.pending(["stepCount", "sleepAsleep", "restingHeartRate"])
  check("whole stays whole", pending.whole == ["stepCount"] && pending.days["stepCount"] == nil, "\(pending)")
  check("day marked", pending.days["sleepAsleep"] == ["2026-11-08"], "\(pending)")
  let read = state.generation
  state.mark(["sleepAsleep"], keys: ["2026-11-09"])
  state.mark(["stepCount"], keys: ["2026-11-09"])
  state.handled(through: read)
  pending = state.pending(["stepCount", "sleepAsleep"])
  check("a mark after the read survives it", pending.days["sleepAsleep"] == ["2026-11-09"], "\(pending)")
  check("a mark under whole after the read keeps it whole", pending.whole == ["stepCount"], "\(pending)")
  state.handled(through: state.generation)
  pending = state.pending(["stepCount", "sleepAsleep"])
  check("all handled", pending.days.isEmpty && pending.whole.isEmpty, "\(pending)")
  let encoded = try! JSONEncoder().encode(state)
  check("state round-trips", (try? JSONDecoder().decode(HealthDays.SyncState.self, from: encoded)) == state)
}

if failures > 0 { exit(1) }
print("ok")
