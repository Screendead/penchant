import Foundation

// A night out on the Lock Screen, the arithmetic alone: when a night ends and
// what it counts. tools/night-plan.test.sh tests it; NightOut.swift runs the
// Live Activity over it.
enum NightPlan {
  // A night ends at this local hour, unless that is under an hour away.
  static let morningHour = 6
  static let shortest: TimeInterval = 60 * 60
  // ActivityKit ends a Live Activity eight hours after it starts ("Plan for
  // Live Activity duration and asset constraints", developer.apple.com), so a
  // night ends then if the morning is further.
  static let longest: TimeInterval = 8 * 60 * 60

  static func endBy(start: Date, calendar: Calendar = .current) -> Date {
    let morning =
      calendar.nextDate(
        after: start.addingTimeInterval(shortest - 1),
        matching: DateComponents(hour: morningHour, minute: 0, second: 0),
        matchingPolicy: .nextTime) ?? start.addingTimeInterval(longest)
    return min(morning, start.addingTimeInterval(longest))
  }
}

// The night running, kept in the App Group so the +1 runs without the app's
// Dart. The app sets base from the entries it has; a log made outside it (the
// +1, a widget, a control, Siri) is added by id until the app has seen it.
struct NightRecord: Codable, Equatable {
  // A queued log is always one of the habit's units (defaultQuantity in
  // lib/writes/log_one.dart).
  static let logQuantity: Double = 1

  // The Live Activity's id.
  let id: String
  let uid: String
  let viceID: String
  let start: Date
  let endBy: Date
  let showsHabit: Bool
  // The habit's total since start, in the entries the app last saw.
  var base: Double
  // Logs made outside the app since that look, by id.
  var outside: [String]

  var count: Double { base + Double(outside.count) * Self.logQuantity }

  func over(at now: Date) -> Bool { now >= endBy }

  // Whether the log changed the count.
  mutating func note(id logID: String, uid logUID: String, viceID logVice: String, at: Date) -> Bool {
    guard logUID == uid, logVice == viceID, at >= start, at < endBy, !outside.contains(logID) else {
      return false
    }
    outside.append(logID)
    return true
  }

  mutating func forget(_ logID: String) -> Bool {
    guard outside.contains(logID) else { return false }
    outside.removeAll { $0 == logID }
    return true
  }

  // The app's look: base totals the habit's entries since start, seen holds
  // their ids, queued the ids of logs still waiting for the app. A log that
  // is neither was refused or undone, and no longer counts.
  mutating func reconcile(base newBase: Double, seen: Set<String>, queued: Set<String>) {
    base = newBase
    outside = outside.filter { !seen.contains($0) && queued.contains($0) }
  }
}
