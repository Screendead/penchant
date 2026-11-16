import Foundation

// Compiled with ios/PenchantWidgets/NightPlan.swift by tools/night-plan.test.sh.

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

func endBy(_ start: Date) -> Date { NightPlan.endBy(start: start, calendar: calendar) }

// The eight-hour limit comes first for an evening start.
check("evening", endBy(at(2026, 11, 14, 19, 20)) == at(2026, 11, 15, 3, 20), "\(endBy(at(2026, 11, 14, 19, 20)))")
// After 22:00 the morning comes first.
check("late", endBy(at(2026, 11, 14, 23, 30)) == at(2026, 11, 15, 6), "\(endBy(at(2026, 11, 14, 23, 30)))")
check("small hours", endBy(at(2026, 11, 15, 2)) == at(2026, 11, 15, 6))
// Under an hour before 06:00, the next morning, so eight hours.
check("just before six", endBy(at(2026, 11, 15, 5, 30)) == at(2026, 11, 15, 13, 30))
check("an hour before six", endBy(at(2026, 11, 15, 5)) == at(2026, 11, 15, 6))
// A night across the clocks going back (London, 25 October 2026, 02:00 to 01:00): eight real hours.
let autumn = at(2026, 10, 24, 23)
check("dst back", endBy(autumn) == at(2026, 10, 25, 6), "\(endBy(autumn))")
check("dst back is under 8 h", endBy(autumn).timeIntervalSince(autumn) == 8 * 3600)
let spring = at(2026, 3, 28, 23)
check("dst forward", endBy(spring) == at(2026, 3, 29, 6), "\(endBy(spring))")
check("never past 8 h", endBy(spring).timeIntervalSince(spring) <= 6 * 3600)

let start = at(2026, 11, 14, 19, 20)
var night = NightRecord(
  id: "a", uid: "u", viceID: "wine", start: start, endBy: endBy(start), showsHabit: false, base: 2, outside: [])
check("starts at base", night.count == 2)
check("a +1 counts", night.note(id: "t1", uid: "u", viceID: "wine", at: start.addingTimeInterval(60)))
check("twice is once", !night.note(id: "t1", uid: "u", viceID: "wine", at: start.addingTimeInterval(60)))
check("another habit", !night.note(id: "t2", uid: "u", viceID: "beer", at: start.addingTimeInterval(60)))
check("another account", !night.note(id: "t3", uid: "v", viceID: "wine", at: start.addingTimeInterval(60)))
check("before the start", !night.note(id: "t4", uid: "u", viceID: "wine", at: start.addingTimeInterval(-1)))
check("after the end", !night.note(id: "t5", uid: "u", viceID: "wine", at: night.endBy))
_ = night.note(id: "t6", uid: "u", viceID: "wine", at: start.addingTimeInterval(120))
check("two taps", night.count == 4, "\(night.count)")
check("undo", night.forget("t6") && night.count == 3)
check("undo twice", !night.forget("t6"))
_ = night.note(id: "t7", uid: "u", viceID: "wine", at: start.addingTimeInterval(180))
_ = night.note(id: "t8", uid: "u", viceID: "wine", at: start.addingTimeInterval(240))
// The app has written t1 (now in its total of 3), t7 waits in the queue, and
// t8 is in neither: refused or undone.
night.reconcile(base: 3, seen: ["e1", "e2", "t1"], queued: ["t7", "other"])
check("reconcile", night.outside == ["t7"] && night.count == 4, "\(night.outside) \(night.count)")
// An entry deleted in the app: the total drops at the next look.
night.reconcile(base: 2, seen: ["e1", "t1"], queued: ["t7"])
check("deleted in the app", night.count == 3)
check("over", !night.over(at: start) && night.over(at: night.endBy))

if failures > 0 {
  print("\(failures) failed")
  exit(1)
}
print("night plan: all passed")
