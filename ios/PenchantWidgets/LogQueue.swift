import Foundation

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

// The one log a widget offers to undo, and until when.
struct LastLog: Codable, Equatable {
  static let undoWindow: TimeInterval = 5
  private static let key = "widgets.lastLog"

  let id: String
  let viceID: String
  let at: Double

  var date: Date { Date(timeIntervalSince1970: at / 1000) }
  var undoUntil: Date { date.addingTimeInterval(Self.undoWindow) }

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
    return modify { $0.append(log) } ? log : nil
  }

  // Drops a log the app has not written yet, or asks it to delete one it has.
  static func undo(_ last: LastLog, uid: String) -> Bool {
    modify { logs in
      if let i = logs.firstIndex(where: { $0.op == .log && $0.id == last.id }) {
        logs.remove(at: i)
      } else if !logs.contains(where: { $0.op == .delete && $0.id == last.id }) {
        logs.append(QueuedLog(op: .delete, id: last.id, uid: uid, viceID: last.viceID, createdAt: last.at))
      }
    }
  }

  // What the app's flush calls once it has handed these to TrackerWrites.
  static func remove(_ done: [QueuedLog]) -> Bool {
    modify { logs in logs.removeAll { done.contains($0) } }
  }
}
