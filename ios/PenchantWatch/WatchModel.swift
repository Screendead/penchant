import Foundation

// What the iPhone and the watch say to each other, and what the watch shows
// from it. Compiled into Runner (ios/Runner/WatchLink.swift sends the context
// and takes the messages), the watch app and its complications. Foundation
// only: tools/watch-model.test.sh runs it on the Mac.

// The iPhone's view of today, replaced whole by each updateApplicationContext.
struct WatchContext: Codable, Equatable {
  static let supportedVersion = 1
  private static let key = "context"

  var version = supportedVersion
  // Nil while nobody is signed in on the iPhone: the watch then shows nothing.
  let uid: String?
  // The iPhone's local day that the totals are for.
  let day: String
  let habits: [Habit]
  // The watch's logs that the totals count, so the watch stops adding them.
  let received: [String]

  struct Habit: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let unitOne: String
    let unitOther: String
    let slot: Int
    // HabitMark's style name: filled, ring or dotted.
    let style: String
    let today: Double

    func unit(_ count: Double) -> String { count == 1 ? unitOne : unitOther }
  }

  static func signedOut(day: String) -> WatchContext {
    WatchContext(uid: nil, day: day, habits: [], received: [])
  }

  var dictionary: [String: Any] {
    [Self.key: (try? JSONEncoder().encode(self)) ?? Data()]
  }

  init(uid: String?, day: String, habits: [Habit], received: [String]) {
    self.uid = uid
    self.day = day
    self.habits = habits
    self.received = received
  }

  init?(dictionary: [String: Any]) {
    guard let data = dictionary[Self.key] as? Data,
      let context = try? JSONDecoder().decode(WatchContext.self, from: data),
      context.version == Self.supportedVersion
    else { return nil }
    self = context
  }
}

// One transferUserInfo from the watch: a log, or the Undo of one.
struct WatchMessage: Equatable {
  enum Op: String {
    case log, undo
  }

  let op: Op
  // The entry's document id, made on the watch, so a second delivery names
  // the same entry.
  let id: String
  // The account the watch showed when the log was made: the iPhone writes it
  // for that account or not at all.
  let uid: String
  let viceID: String
  // The tap, in milliseconds since the epoch.
  let at: Double

  var dictionary: [String: Any] {
    ["op": op.rawValue, "id": id, "uid": uid, "viceID": viceID, "at": at]
  }

  init(op: Op, log: WatchLog) {
    self.op = op
    id = log.id
    uid = log.uid
    viceID = log.viceID
    at = log.at
  }

  init?(dictionary: [String: Any]) {
    guard let op = (dictionary["op"] as? String).flatMap(Op.init),
      let id = dictionary["id"] as? String, WatchLog.validID(id),
      let uid = dictionary["uid"] as? String, (1...128).contains(uid.count),
      let viceID = dictionary["viceID"] as? String, (1...128).contains(viceID.count), !viceID.contains("/"),
      let at = dictionary["at"] as? Double, at > 0
    else { return nil }
    self.op = op
    self.id = id
    self.uid = uid
    self.viceID = viceID
    self.at = at
  }
}

// A log made on the watch, kept there until the iPhone's context counts it.
struct WatchLog: Codable, Equatable {
  // The app's Undo bar (undo-duration).
  static let undoWindow: TimeInterval = 8
  // Past this a log the iPhone has not counted is said to be waiting.
  static let waitingAfter: TimeInterval = 20
  static let keptFor: TimeInterval = 3 * 24 * 60 * 60

  let id: String
  let uid: String
  let viceID: String
  let at: Double
  var undone = false
  // Given to WCSession, which delivers it even if the app ends first. A log
  // undone before that is never sent.
  var handed = false
  var undoHanded = false

  var date: Date { Date(timeIntervalSince1970: at / 1000) }
  var undoUntil: Date { date.addingTimeInterval(Self.undoWindow) }

  init(uid: String, viceID: String, at date: Date) {
    id = Self.newID()
    self.uid = uid
    self.viceID = viceID
    at = (date.timeIntervalSince1970 * 1000).rounded()
  }

  // Firestore's own auto-id alphabet and length, as LogQueue.newID.
  static func newID() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    var generator = SystemRandomNumberGenerator()
    return String((0..<20).map { _ in alphabet.randomElement(using: &generator)! })
  }

  static func validID(_ id: String) -> Bool {
    id.count == 20 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }

  // What still matters at now: another account's logs are the system's to
  // deliver, a counted log is in the context's totals once its Undo has
  // gone, and an undone one only corrects today's.
  static func pruned(_ outbox: [WatchLog], context: WatchContext?, now: Date, calendar: Calendar = .current)
    -> [WatchLog]
  {
    guard let context else { return outbox }
    let today = WatchDay.key(now, calendar)
    let counted = Set(context.received)
    return outbox.filter { log in
      guard log.uid == context.uid, now.timeIntervalSince(log.date) < keptFor else { return false }
      let day = WatchDay.key(log.date, calendar)
      if log.undone { return day == today }
      return now < log.undoUntil || !(counted.contains(log.id) && context.day >= day)
    }
  }
}

// The app's dayKey: the local calendar date, which sorts as text.
enum WatchDay {
  static func key(_ date: Date, _ calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func next(after date: Date, _ calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86400)
  }
}

// What the watch shows at now.
struct WatchBoard: Equatable {
  enum State: Equatable {
    // No context has ever arrived.
    case noData
    case signedOut
    case habits
  }

  struct Row: Equatable, Identifiable {
    let habit: WatchContext.Habit
    let total: Double

    var id: String { habit.id }
    var unit: String { habit.unit(total) }
  }

  let state: State
  let rows: [Row]
  // False on a day the iPhone has not reported: its totals are another
  // day's, so each row counts only this watch's logs of today.
  let current: Bool
  // Logs the iPhone has yet to count, past the moment a transfer usually takes.
  let waiting: Int

  init(context: WatchContext?, outbox: [WatchLog], now: Date, calendar: Calendar = .current) {
    guard let context else {
      self.init(state: .noData)
      return
    }
    guard let uid = context.uid else {
      self.init(state: .signedOut)
      return
    }
    let today = WatchDay.key(now, calendar)
    let mine = outbox.filter { $0.uid == uid }
    let counted = Set(context.received)
    let current = context.day == today
    let rows = context.habits.map { habit in
      let own = mine.filter { $0.viceID == habit.id && WatchDay.key($0.date, calendar) == today }
      let total =
        current
        ? habit.today + Double(own.filter { !$0.undone && !counted.contains($0.id) }.count)
          - Double(own.filter { $0.undone && counted.contains($0.id) }.count)
        : Double(own.filter { !$0.undone }.count)
      return Row(habit: habit, total: max(0, total))
    }
    let waiting = mine.filter {
      !$0.undone && !counted.contains($0.id) && now.timeIntervalSince($0.date) >= WatchLog.waitingAfter
    }.count
    self.init(state: .habits, rows: rows, current: current, waiting: waiting)
  }

  private init(state: State, rows: [Row] = [], current: Bool = true, waiting: Int = 0) {
    self.state = state
    self.rows = rows
    self.current = current
    self.waiting = waiting
  }

  func row(_ id: String?) -> Row? { rows.first { $0.id == id } }
}

// Opens the watch app on a habit, from a complication.
enum WatchHabitLink {
  static let scheme = "com.screendead.penchant"
  static let host = "log"

  static func url(_ habitID: String) -> URL? { URL(string: "\(scheme)://\(host)/\(habitID)") }

  static func habitID(_ url: URL) -> String? {
    url.scheme?.lowercased() == scheme && url.host?.lowercased() == host ? url.lastPathComponent : nil
  }
}

func watchCount(_ value: Double) -> String {
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.maximumFractionDigits = 1
  return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
