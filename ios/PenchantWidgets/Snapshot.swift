import Foundation

// Written by the app through ios/Runner/WidgetBridge.swift; the shape is
// widgetSnapshot's in lib/data/widget_snapshot.dart. A sandboxed Mac app's
// group takes the team ID as its prefix ("Configuring app groups"), and must
// match macos/Runner/*.entitlements.
#if os(macOS)
  let appGroup = "8N575942RT.com.screendead.penchant"
#else
  let appGroup = "group.com.screendead.penchant"
#endif
let snapshotKey = "widgets.snapshot"

struct Snapshot: Decodable {
  static let supportedVersion = 1

  let version: Int
  // Absent from snapshots written before logging from a widget existed.
  let uid: String?
  let days: [String]
  var habits: [Habit]
  let top: [String]

  struct Habit: Decodable, Identifiable {
    let id: String
    let name: String
    let unitOne: String
    let unitOther: String
    let slot: Int
    let style: MarkStyle
    var week: [Double]
    var weekEntries: [Int]
    var entries30: Int

    func unit(_ count: Double) -> String { count == 1 ? unitOne : unitOther }
  }

  enum MarkStyle: String, Decodable {
    case filled, ring, dotted
  }

  // The app's last snapshot plus the logs still waiting in LogQueue for it to
  // write, so a tap shows at once.
  static func load() -> Snapshot? {
    guard let json = UserDefaults(suiteName: appGroup)?.string(forKey: snapshotKey),
      var snapshot = try? JSONDecoder().decode(Snapshot.self, from: Data(json.utf8)),
      snapshot.version == supportedVersion
    else { return nil }
    snapshot.add(LogQueue.read())
    return snapshot
  }

  mutating func add(_ queued: [QueuedLog]) {
    for log in queued where log.op == .log && log.uid == uid {
      guard let h = habits.firstIndex(where: { $0.id == log.viceID }) else { continue }
      habits[h].entries30 += 1
      if let d = days.firstIndex(of: dayKey(log.date)), habits[h].week.indices.contains(d),
        habits[h].weekEntries.indices.contains(d)
      {
        habits[h].week[d] += 1
        habits[h].weekEntries[d] += 1
      }
    }
  }

  func habit(_ id: String) -> Habit? { habits.first { $0.id == id } }

  // The configured habits that still exist, else the 30-day top.
  func shown(_ chosen: [String], count: Int) -> [Habit] {
    let picked = chosen.compactMap(habit)
    let ranked = top.compactMap(habit) + habits.filter { !top.contains($0.id) }
    return Array((picked.isEmpty ? ranked : picked).prefix(count))
  }
}

// One habit over the seven days ending on the entry's day. A day the snapshot
// does not cover (the app has not run since) reads as nil, drawn as no data.
struct HabitWeek: Identifiable {
  let habit: Snapshot.Habit
  let values: [Double?]
  let entries: [Int?]

  var id: String { habit.id }
  var total: Double { values.compactMap { $0 }.reduce(0, +) }
  var entryCount: Int { entries.compactMap { $0 }.reduce(0, +) }
  var peak: Double { values.compactMap { $0 }.max() ?? 0 }
}

struct Week {
  let days: [Date]
  let habits: [HabitWeek]
  let covered: [Bool]

  var entryCount: Int { habits.map(\.entryCount).reduce(0, +) }

  static let length = 7

  init(snapshot: Snapshot, endingOn date: Date, calendar: Calendar = .current) {
    let today = calendar.startOfDay(for: date)
    let days = (0..<Week.length).reversed().map {
      calendar.date(byAdding: .day, value: -$0, to: today)!
    }
    let indexes = days.map { snapshot.days.firstIndex(of: dayKey($0, calendar)) }
    self.days = days
    self.covered = indexes.map { $0 != nil }
    self.habits = snapshot.habits.map { habit in
      HabitWeek(
        habit: habit,
        values: indexes.map { i in i.flatMap { habit.week.indices.contains($0) ? habit.week[$0] : nil } },
        entries: indexes.map { i in
          i.flatMap { habit.weekEntries.indices.contains($0) ? habit.weekEntries[$0] : nil }
        })
    }
  }
}

// The app's dayKey: the local calendar date.
func dayKey(_ date: Date, _ calendar: Calendar = .current) -> String {
  let parts = calendar.dateComponents([.year, .month, .day], from: date)
  return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

func formatCount(_ value: Double) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 1
  return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

extension HabitWeek {
  // English plurals whatever the region, as the app's pluralWord.
  var totalLabel: String {
    "\(formatCount(total)) \(total == 1 ? habit.unitOne : habit.unitOther)"
  }
}
