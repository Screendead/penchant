import Foundation

#if canImport(WatchConnectivity) && os(iOS)
  import WatchConnectivity
  import WidgetKit
#endif

// The iPhone's side of the Apple Watch app (ios/PenchantWatch). A log tapped
// on the watch arrives as a WatchMessage and joins LogQueue, so the app writes
// it sealed exactly as it writes a widget's; the watch gets back a
// WatchContext built from the widgets' snapshot. Nothing else crosses: no key,
// no token, no entry.

// An entry the app wrote, or deleted, that the stored snapshot does not show
// yet: the headless flush (BackgroundFlush) saves no snapshot, and a
// foreground one may take its log off the queue before the next save.
struct WatchLedgerEntry: Codable, Equatable {
  let uid: String
  let viceID: String
  let createdAt: Double
  let delta: Int

  var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }

  // What removing these from the queue changed on the server. A log and its
  // own delete were both dropped unwritten. reflected names the entries a
  // snapshot saved since has already counted.
  static func written(_ done: [QueuedLog], reflected: Set<String>) -> [WatchLedgerEntry] {
    let logged = Set(done.filter { $0.op == .log }.map(\.id))
    let deleted = Set(done.filter { $0.op == .delete }.map(\.id))
    return done.compactMap { log in
      guard !reflected.contains(log.key), !(logged.contains(log.id) && deleted.contains(log.id)) else { return nil }
      return WatchLedgerEntry(
        uid: log.uid, viceID: log.viceID, createdAt: log.createdAt, delta: log.op == .log ? 1 : -1)
    }
  }
}

// What the stored snapshot and the queue do not say between them about the
// entries the app's flushes have written.
struct WatchTally: Equatable {
  // Handed to a foreground flush, which writes them at once.
  var flushing: Set<String> = []
  // Of those, the ones a snapshot saved since counts.
  var reflected: Set<String> = []
  var ledger: [WatchLedgerEntry] = []

  // The app's flush read the queue: Dart writes every log past its hold, and
  // every delete, before it answers. The headless engine never says so: it
  // saves no snapshot after it writes.
  // A log queued with its own delete is dropped unwritten (readyLogs).
  mutating func handedOut(_ logs: [QueuedLog], now: Date) {
    let logged = Set(logs.filter { $0.op == .log }.map(\.id))
    let deleted = Set(logs.filter { $0.op == .delete }.map(\.id))
    flushing = Set(
      logs.filter {
        !(logged.contains($0.id) && deleted.contains($0.id))
          && ($0.op == .delete || $0.date.addingTimeInterval(queuedLogHold) <= now)
      }.map(\.key))
  }

  // Dart's snapshot counts everything written so far.
  mutating func snapshotSaved(queue: [QueuedLog]) {
    reflected = reflected.union(flushing).intersection(queue.map(\.key))
    ledger = []
  }

  mutating func removed(_ done: [QueuedLog], now: Date, calendar: Calendar = .current) {
    let today = dayKey(now, calendar)
    ledger = (ledger + WatchLedgerEntry.written(done, reflected: reflected)).filter {
      dayKey($0.date, calendar) == today
    }
    let keys = Set(done.map(\.key))
    flushing.subtract(keys)
    reflected.subtract(keys)
  }
}

extension WatchContext {
  // The widgets' top habits (r10-widget-top), in the app's order.
  static let habitCount = 8

  // Today's totals as the iPhone knows them: the stored snapshot's column for
  // today (none if the app has not run today), the queue's logs still to
  // write, and the ledger. A queued delete with no queued log is of a written
  // entry, so it counts one fewer.
  static func build(
    snapshot: Snapshot?, queue: [QueuedLog], tally: WatchTally, received: [String], now: Date,
    calendar: Calendar = .current
  ) -> WatchContext {
    let today = dayKey(now, calendar)
    guard let snapshot, let uid = snapshot.uid else { return .signedOut(day: today) }
    let column = snapshot.days.firstIndex(of: today)
    let pending = queue.filter {
      $0.uid == uid && dayKey($0.date, calendar) == today && !tally.reflected.contains($0.key)
    }
    let shown = snapshot.top.isEmpty ? Set(snapshot.habits.prefix(habitCount).map(\.id)) : Set(snapshot.top)
    let habits = snapshot.habits.filter { shown.contains($0.id) }.map { habit in
      let mine = pending.filter { $0.viceID == habit.id }
      let logs = Set(mine.filter { $0.op == .log }.map(\.id))
      let deletes = Set(mine.filter { $0.op == .delete }.map(\.id))
      let written = tally.ledger.filter {
        $0.uid == uid && $0.viceID == habit.id && dayKey($0.date, calendar) == today
      }
      let base = column.flatMap { habit.week.indices.contains($0) ? habit.week[$0] : nil } ?? 0
      let total =
        base + Double(logs.subtracting(deletes).count) - Double(deletes.subtracting(logs).count)
        + Double(written.map(\.delta).reduce(0, +))
      return Habit(
        id: habit.id, name: habit.name, unitOne: habit.unitOne, unitOther: habit.unitOther, slot: habit.slot,
        style: habit.style.rawValue, today: max(0, total))
    }
    return WatchContext(uid: uid, day: today, habits: habits, received: received)
  }
}

// The watch's logs the iPhone has taken, newest last: a second delivery of
// one is dropped, an Undo counts only for one of them, and the context lists
// those not undone.
struct WatchSeen: Codable, Equatable {
  static let kept = 200
  static let listed = 60

  struct Entry: Codable, Equatable {
    let id: String
    var undone: Bool
  }

  var entries: [Entry] = []

  var received: [String] { entries.filter { !$0.undone }.suffix(Self.listed).map(\.id) }

  // False for a log already taken.
  mutating func take(_ id: String) -> Bool {
    guard !entries.contains(where: { $0.id == id }) else { return false }
    entries = Array((entries + [Entry(id: id, undone: false)]).suffix(Self.kept))
    return true
  }

  // False unless the log was taken and is not yet undone.
  mutating func undo(_ id: String) -> Bool {
    guard let i = entries.firstIndex(where: { $0.id == id && !$0.undone }) else { return false }
    entries[i].undone = true
    return true
  }
}

#if canImport(WatchConnectivity) && os(iOS)
  final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    private static let seenKey = "watch.seen"
    private static let ledgerKey = "watch.ledger"

    // WCSession calls on its own queue, the bridge on the main one.
    private let lock = NSLock()
    private var tally = WatchTally()
    private var sent: WatchContext?

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    func start() {
      guard WCSession.isSupported() else { return }
      // An earlier run's headless flush may have written since the last save.
      lock.withLock { tally.ledger = load(Self.ledgerKey) ?? [] }
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    func handedOut(_ logs: [QueuedLog]) {
      lock.withLock { tally.handedOut(logs, now: Date()) }
    }

    func snapshotSaved() {
      let queue = LogQueue.read()
      change { $0.snapshotSaved(queue: queue) }
    }

    func cleared() {
      change { $0 = WatchTally() }
    }

    func removed(_ done: [QueuedLog]) {
      change { $0.removed(done, now: Date()) }
    }

    private func change(_ apply: (inout WatchTally) -> Void) {
      lock.withLock {
        apply(&tally)
        save(tally.ledger, Self.ledgerKey)
      }
      send()
    }

    // Tells the watch what the iPhone knows now. A context the session cannot
    // take yet goes when it activates or the watch app appears.
    func send() {
      guard WCSession.isSupported() else { return }
      let session = WCSession.default
      guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
      let queue = LogQueue.read()
      lock.withLock {
        let context = WatchContext.build(
          snapshot: Snapshot.stored(), queue: queue, tally: tally,
          received: (load(Self.seenKey) ?? WatchSeen()).received, now: Date())
        guard context != sent else { return }
        do {
          try session.updateApplicationContext(context.dictionary)
          sent = context
        } catch {
          NSLog("Penchant: the watch did not take the context: %@", error.localizedDescription)
        }
      }
    }

    private func resend() {
      lock.withLock { sent = nil }
      send()
    }

    private func receive(_ message: WatchMessage) {
      switch message.op {
      case .log:
        // The watch's clock, but never ahead of this one.
        let log = QueuedLog(
          op: .log, id: message.id, uid: message.uid, viceID: message.viceID,
          createdAt: min(message.at, (Date().timeIntervalSince1970 * 1000).rounded()), via: "watch")
        guard seen({ $0.take(message.id) }) else { return }
        guard LogQueue.add(log) else {
          NSLog("Penchant: a log from the watch could not be queued")
          return
        }
        if #available(iOS 17.0, *) {
          Task { await NightOut.noted(log) }
        }
      case .undo:
        // A delete for an entry that never arrived would be refused by the
        // rules and shown as a failure.
        guard seen({ $0.undo(message.id) }) else { return }
        _ = LogQueue.undo(LastLog(id: message.id, viceID: message.viceID, at: message.at), uid: message.uid)
        if #available(iOS 17.0, *) {
          Task { await NightOut.forget(message.id) }
        }
      }
      if #available(iOS 17.0, *) {
        reloadEverything()
      } else {
        WidgetCenter.shared.reloadAllTimelines()
      }
      send()
    }

    private func seen(_ apply: (inout WatchSeen) -> Bool) -> Bool {
      lock.withLock {
        var seen: WatchSeen = load(Self.seenKey) ?? WatchSeen()
        guard apply(&seen) else { return false }
        save(seen, Self.seenKey)
        return true
      }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
      defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
      defaults?.set(try? JSONEncoder().encode(value), forKey: key)
    }

    func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
      resend()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    // Another watch took over: Apple's docs have the app activate again to
    // reach it.
    func sessionDidDeactivate(_ session: WCSession) {
      session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
      resend()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
      guard let message = WatchMessage(dictionary: userInfo) else { return }
      receive(message)
    }
  }
#endif
