import Foundation

#if os(iOS)
  import BackgroundTasks
#endif

// A log made outside the app: by a widget button, a control, Siri or
// Shortcuts. The app writes it to Firestore through TrackerWrites
// (lib/widget_bridge/log_queue.dart), so this side never holds the
// encryption key or an Auth token, and the entry is stored exactly as one
// logged in the app. The id becomes the document id, so a second flush of the
// same entry writes the same document.
struct QueuedLog: Codable, Equatable {
  enum Op: String, Codable {
    // Record one of viceID at createdAt.
    case log
    // Delete the entry with this id: an Undo that came after the app had
    // already written the log.
    case delete
  }

  let op: Op
  let id: String
  let uid: String
  let viceID: String
  // Milliseconds since the epoch: the tap, not the flush, so a log the app
  // writes hours later still lands on the day it was made.
  let createdAt: Double

  var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}

// The one log a widget offers to undo, and until when; and to say what was
// going on, for longer.
struct LastLog: Codable, Equatable {
  static let undoWindow: TimeInterval = 5
  // Long enough to notice the link after the tap; the Undo is long gone.
  static let askWindow: TimeInterval = 5 * 60
  private static let key = "widgets.lastLog"

  let id: String
  let viceID: String
  let at: Double
  // Its "What was going on?" has been opened, so it is offered no more.
  var asked: Bool?

  var date: Date { Date(timeIntervalSince1970: at / 1000) }
  var undoUntil: Date { date.addingTimeInterval(Self.undoWindow) }
  var askUntil: Date { date.addingTimeInterval(Self.askWindow) }

  func askable(at now: Date) -> Bool { asked != true && now < askUntil }

  // Still to undo or to ask about at now.
  static func current(at now: Date = Date()) -> LastLog? {
    load().flatMap { now < $0.undoUntil || $0.askable(at: now) ? $0 : nil }
  }

  static func load() -> LastLog? {
    guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(LastLog.self, from: data)
  }

  static func save(_ log: LastLog?) {
    let defaults = UserDefaults(suiteName: appGroup)
    if let log, let data = try? JSONEncoder().encode(log) {
      defaults?.set(data, forKey: key)
    } else {
      defaults?.removeObject(forKey: key)
    }
  }
}

// Opens Penchant at a log made outside it, to say what was going on: the
// widgets' Link, and the menu bar helper. It carries the entry's id only:
// what is picked is journal content, sealed in the app, which also writes the
// queued log first (lib/widget_bridge/entry_prompt.dart). Registered in each
// Runner's Info.plist (CFBundleURLTypes).
enum EntryLink {
  static let scheme = "com.screendead.penchant"
  static let host = "what-was-going-on"

  static func url(_ log: LastLog) -> URL? { URL(string: "\(scheme)://\(host)/\(log.id)") }

  static func activityID(_ url: URL) -> String? {
    guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return nil }
    let id = url.lastPathComponent
    guard (1...64).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      return nil
    }
    return id
  }
}

// Posted by whichever process changes the queue, heard by a running app.
let queueChangedNotification = "com.screendead.penchant.log-queue-changed"

#if os(macOS)
  // The background-only app (macos/PenchantSync) the menu bar helper launches
  // to write the queue while Penchant is closed.
  let syncAppID = "com.screendead.penchant.sync"

  // App Group key between the menu bar helper and PenchantSync, which leaves
  // BackgroundFlushOutcome's name in it as it quits.
  enum FlushHandoff {
    static let outcome = "menubar.flushOutcome"
  }

  // Penchant posts it at each launch, to bring back a menu bar item the user
  // hid with its Quit (the helper keeps running, to go on flushing).
  let showMenuBarNotification = "com.screendead.penchant.menubar.show"

  // The menu bar helper's last sign of life, in seconds since 1970. Only a
  // running helper launches Penchant to write what the widgets queue, and a
  // killed one says nothing, so the widgets judge it by this. A napped
  // helper's timer can fire late, so a beat counts for several intervals.
  enum HelperHeartbeat {
    static let key = "menubar.heartbeat"
    static let interval: TimeInterval = 60
    static let staleAfter: TimeInterval = 10 * 60

    static func beat(now: Date = Date()) {
      UserDefaults(suiteName: appGroup)?.set(now.timeIntervalSince1970, forKey: key)
    }

    static func last() -> Date? {
      let seconds = UserDefaults(suiteName: appGroup)?.double(forKey: key) ?? 0
      return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }
  }
#endif

// What a widget says about its queued logs: on the Mac, that they wait for
// Penchant while no helper is alive to launch it. iOS writes them from the
// app's own process (LogIntents.swift), so there it says nothing.
struct QueuedWait: Equatable {
  // Past a log's hold, a live helper or a running app writes it within
  // seconds; this much later it is waiting.
  static let grace: TimeInterval = 30
  // A helper alive now may be killed before it launches Penchant, and nothing
  // reloads the widgets then. Each reload counts against WidgetKit's budget.
  static let recheckEvery: TimeInterval = 15 * 60

  static let none = QueuedWait(from: nil, recheck: nil)

  // From when the widget says so; nil, it does not.
  let from: Date?
  // When the widget should ask again.
  let recheck: Date?

  func waiting(at date: Date) -> Bool { from.map { date >= $0 } ?? false }

  // Adds the moment the notice starts to a timeline's entry dates.
  func dates(_ dates: [Date], now: Date) -> [Date] {
    guard let from, from > now, !dates.contains(from) else { return dates }
    return (dates + [from]).sorted()
  }

  static func current(now: Date = Date()) -> QueuedWait {
    #if os(macOS)
      return judge(pending: LogQueue.pending(), heartbeat: HelperHeartbeat.last(), now: now)
    #else
      return .none
    #endif
  }

  #if os(macOS)
    // A stale helper that comes back reloads the widgets (FlushLauncher.beat),
    // so only a fresh one needs a recheck.
    static func judge(pending: [QueuedLog], heartbeat: Date?, now: Date) -> QueuedWait {
      guard let oldest = pending.map(\.date).min() else { return .none }
      // abs: a clock set back must not keep a dead helper's last beat fresh.
      if let heartbeat, abs(now.timeIntervalSince(heartbeat)) <= HelperHeartbeat.staleAfter {
        return QueuedWait(from: nil, recheck: now.addingTimeInterval(recheckEvery))
      }
      return QueuedWait(from: max(now, oldest.addingTimeInterval(queuedLogHold + grace)), recheck: nil)
    }
  #endif
}

// queuedLogHold in lib/data/queued_log.dart: the app writes a log only once it
// is this old, past the widget's Undo window.
let queuedLogHold: TimeInterval = 7

// A JSON file in the App Group container. The app, the widget extension and
// an intent run in separate processes, so every read-modify-write goes
// through NSFileCoordinator.
enum LogQueue {
  static var url: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("log-queue.json")
  }

  static func read() -> [QueuedLog] {
    guard let url else { return [] }
    var logs: [QueuedLog] = []
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in
      logs = decode(url)
    }
    return logs
  }

  @discardableResult
  static func modify(_ change: (inout [QueuedLog]) -> Void) -> Bool {
    guard let url else { return false }
    var saved = false
    var error: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { url in
      var logs = decode(url)
      change(&logs)
      guard let data = try? JSONEncoder().encode(logs) else { return }
      saved = (try? data.write(to: url, options: .atomic)) != nil
    }
    return saved && error == nil
  }

  private static func decode(_ url: URL) -> [QueuedLog] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([QueuedLog].self, from: data)) ?? []
  }

  // Firestore's own auto-id alphabet and length.
  static func newID() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    var generator = SystemRandomNumberGenerator()
    return String((0..<20).map { _ in alphabet.randomElement(using: &generator)! })
  }

  static func log(uid: String, viceID: String, at date: Date = Date()) -> QueuedLog? {
    let log = QueuedLog(
      op: .log, id: newID(), uid: uid, viceID: viceID, createdAt: (date.timeIntervalSince1970 * 1000).rounded())
    guard modify({ $0.append(log) }) else { return nil }
    requestFlush()
    return log
  }

  // Drops a log the app has not written yet, or asks it to delete one it has.
  // Past the Undo window the app may already be writing the log (it waits 7 s,
  // queuedLogHold in lib/data/queued_log.dart), so a late Undo always queues
  // a delete: the app drops both if neither was written, or deletes after.
  static func undo(_ last: LastLog, uid: String, now: Date = Date()) -> Bool {
    defer { requestFlush() }
    return modify { logs in
      if now < last.undoUntil, let i = logs.firstIndex(where: { $0.op == .log && $0.id == last.id }) {
        logs.remove(at: i)
      } else if !logs.contains(where: { $0.op == .delete && $0.id == last.id }) {
        logs.append(QueuedLog(op: .delete, id: last.id, uid: uid, viceID: last.viceID, createdAt: last.at))
      }
    }
  }

  // Logs the app has yet to write for the signed-in user. Another account's
  // wait for that account, so they never keep a refresh coming.
  static func pending() -> [QueuedLog] {
    guard let uid = Snapshot.load()?.uid else { return [] }
    return read().filter { $0.uid == uid }
  }

  // Tells a running app at once (it flushes over its method channel). With the
  // app closed, the Mac's menu bar helper hears it and launches the app hidden
  // to flush, and iOS asks for a background refresh, so a log can reach
  // Firestore before the next launch. Only ever while logs are pending:
  // an empty queue schedules nothing.
  static func requestFlush() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(queueChangedNotification as CFString), nil, nil,
      true)
    #if os(iOS)
      scheduleRefresh()
      flushInThisProcess?()
    #endif
  }

  #if os(iOS)
    // Info.plist's BGTaskSchedulerPermittedIdentifiers lists it; the app
    // registers the handler (ios/Runner/WidgetBridge.swift).
    static let refreshTaskID = "com.screendead.penchant.flush-log-queue"

    // Set by the app (BackgroundFlush.register in ios/Runner/WidgetBridge.swift)
    // and nil in the extension. The log intents run in the app's process
    // (LiveActivityIntent in LogIntents.swift), so there a tap is written
    // within seconds; the refresh above stays as the fallback.
    static var flushInThisProcess: (() -> Void)?

    // When the youngest of these logs is past its Undo hold.
    static func due(_ logs: [QueuedLog]) -> Date {
      max(logs.map { $0.date.addingTimeInterval(queuedLogHold) }.max() ?? Date(), Date())
    }

    // The system picks the time; iOS keeps at most one refresh request per
    // app, and a new one replaces it. Apple allows a submit "from some
    // extensions"; where a widget's is refused, the app asks when it goes to
    // the background.
    static func scheduleRefresh() {
      let logs = pending()
      guard !logs.isEmpty else {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        return
      }
      let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
      request.earliestBeginDate = due(logs)
      try? BGTaskScheduler.shared.submit(request)
    }
  #endif

  // What the app's flush calls once it has handed these to TrackerWrites.
  static func remove(_ done: [QueuedLog]) -> Bool {
    modify { logs in logs.removeAll { done.contains($0) } }
  }
}
