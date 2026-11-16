import Foundation

// Compiled with the watch's model and the iPhone's totals by tools/watch-model.test.sh. It plays the
// iPhone (the stored snapshot, the queue, the tally, the seen list) and the watch (the context it last
// got, its outbox) by hand, as ios/Runner/WatchLink.swift and ios/PenchantWatch/WatchSession.swift do.

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!
var failures = 0

func at(_ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: mi, second: s))!
}

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
  if !ok {
    failures += 1
    print("FAIL: \(name) \(detail())")
  }
}

func snapshot(endingOn day: Int, coffee: Double, uid: String? = "u1") -> Snapshot {
  let days = (0..<7).reversed().map { dayKey(at(day - $0), calendar) }
  let json: [String: Any] = [
    "version": 1, "uid": uid as Any, "days": days, "top": ["coffee", "wine"],
    "habits": [
      [
        "id": "coffee", "name": "Coffee", "unitOne": "cup", "unitOther": "cups", "slot": 0, "style": "filled",
        "week": [0, 0, 0, 0, 0, 0, coffee], "weekEntries": [0, 0, 0, 0, 0, 0, Int(coffee)], "entries30": 9,
      ],
      [
        "id": "wine", "name": "Wine", "unitOne": "glass", "unitOther": "glasses", "slot": 1, "style": "ring",
        "week": [0, 0, 0, 0, 0, 0, 0], "weekEntries": [0, 0, 0, 0, 0, 0, 0], "entries30": 2,
      ],
      [
        "id": "tea", "name": "Tea", "unitOne": "cup", "unitOther": "cups", "slot": 2, "style": "filled",
        "week": [0, 0, 0, 0, 0, 0, 5], "weekEntries": [0, 0, 0, 0, 0, 0, 5], "entries30": 1,
      ],
    ],
  ]
  return try! JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: json))
}

struct Phone {
  var stored: Snapshot?
  var queue: [QueuedLog] = []
  var tally = WatchTally()
  var seen = WatchSeen()

  func context(_ now: Date) -> WatchContext {
    WatchContext.build(
      snapshot: stored, queue: queue, tally: tally, received: seen.received, now: now, calendar: calendar)
  }

  // WatchLink.receive, with LogQueue.undo's rule for an Undo.
  mutating func receive(_ dictionary: [String: Any], now: Date) {
    guard let message = WatchMessage(dictionary: dictionary) else { return }
    switch message.op {
    case .log:
      guard seen.take(message.id) else { return }
      queue.append(
        QueuedLog(
          op: .log, id: message.id, uid: message.uid, viceID: message.viceID, createdAt: message.at, via: "watch"))
    case .undo:
      guard seen.undo(message.id) else { return }
      let last = LastLog(id: message.id, viceID: message.viceID, at: message.at)
      if now < last.undoUntil, let i = queue.firstIndex(where: { $0.op == .log && $0.id == message.id }) {
        queue.remove(at: i)
      } else {
        queue.append(
          QueuedLog(op: .delete, id: message.id, uid: message.uid, viceID: message.viceID, createdAt: message.at))
      }
    }
  }

  // The flush took these off the queue (removeLogs).
  mutating func remove(_ done: [QueuedLog], now: Date) {
    queue.removeAll { done.contains($0) }
    tally.removed(done, now: now, calendar: calendar)
  }

  // Dart saved a snapshot that counts every written entry.
  mutating func save(_ snapshot: Snapshot) {
    stored = snapshot
    tally.snapshotSaved(queue: queue)
  }
}

struct Watch {
  var context: WatchContext?
  var outbox: [WatchLog] = []

  func coffee(_ now: Date) -> Double? {
    WatchBoard(context: context, outbox: outbox, now: now, calendar: calendar).row("coffee")?.total
  }

  mutating func take(_ context: WatchContext, now: Date) {
    self.context = context
    outbox = WatchLog.pruned(outbox, context: context, now: now, calendar: calendar)
  }

  mutating func tap(_ now: Date) -> [String: Any] {
    var log = WatchLog(uid: context!.uid!, viceID: "coffee", at: now)
    log.handed = true
    outbox.append(log)
    return WatchMessage(op: .log, log: log).dictionary
  }

  mutating func undoLast() -> [String: Any] {
    outbox[outbox.count - 1].undone = true
    return WatchMessage(op: .undo, log: outbox[outbox.count - 1]).dictionary
  }
}

// The morning coffee with the iPhone closed: its snapshot is yesterday's.
do {
  var phone = Phone(stored: snapshot(endingOn: 15, coffee: 4))
  var watch = Watch()
  watch.take(phone.context(at(15, 22)), now: at(15, 22))
  check("yesterday's total while it is yesterday", watch.coffee(at(15, 22)) == 4)
  check("a new day starts at none", watch.coffee(at(16, 7)) == 0)
  check("a new day is said", !WatchBoard(context: watch.context, outbox: [], now: at(16, 7), calendar: calendar).current)

  let log = watch.tap(at(16, 7, 30))
  check("the tap shows at once", watch.coffee(at(16, 7, 30, 1)) == 1)

  phone.receive(log, now: at(16, 7, 30, 2))
  watch.take(phone.context(at(16, 7, 30, 2)), now: at(16, 7, 30, 2))
  check("the iPhone has it queued", watch.coffee(at(16, 7, 30, 3)) == 1, "\(String(describing: watch.coffee(at(16, 7, 30, 3))))")
  check("a counted log stays while it can be undone", watch.outbox.count == 1)

  // The headless flush writes it and saves no snapshot.
  phone.remove(phone.queue, now: at(16, 7, 30, 9))
  watch.take(phone.context(at(16, 7, 30, 9)), now: at(16, 7, 30, 9))
  check("written with the app closed", watch.coffee(at(16, 7, 31)) == 1, "\(String(describing: watch.coffee(at(16, 7, 31))))")
  check("then leaves the outbox", watch.outbox.isEmpty)

  // The app opens and saves a snapshot that counts the entry.
  phone.save(snapshot(endingOn: 16, coffee: 1))
  watch.take(phone.context(at(16, 9)), now: at(16, 9))
  check("counted once after the app opens", watch.coffee(at(16, 9)) == 1, "\(String(describing: watch.coffee(at(16, 9))))")
  check("the ledger ends with the save", phone.tally.ledger.isEmpty)

  // A second delivery of the same log is dropped.
  phone.receive(log, now: at(16, 9, 1))
  check("a redelivered log is not queued", phone.queue.isEmpty)
}

// The app running: its flush writes, a snapshot follows, the server answers.
do {
  var phone = Phone(stored: snapshot(endingOn: 16, coffee: 2))
  var watch = Watch()
  watch.take(phone.context(at(16, 10)), now: at(16, 10))
  phone.receive(watch.tap(at(16, 10)), now: at(16, 10, 0, 1))
  check("queued over a current snapshot", phone.context(at(16, 10, 0, 2)).habits[0].today == 3)

  phone.tally.handedOut(phone.queue, now: at(16, 10, 0, 3))
  check("a log in its hold is not being written", phone.tally.flushing.isEmpty)
  phone.tally.handedOut(phone.queue, now: at(16, 10, 0, 8))
  phone.save(snapshot(endingOn: 16, coffee: 3))
  check("not twice while the server has yet to answer", phone.context(at(16, 10, 0, 9)).habits[0].today == 3)
  phone.remove(phone.queue, now: at(16, 10, 0, 10))
  check("nor after it has", phone.context(at(16, 10, 0, 10)).habits[0].today == 3)
  check("a counted write leaves no ledger", phone.tally.ledger.isEmpty)

  // The server answers before the next snapshot is saved.
  phone.receive(watch.tap(at(16, 11)), now: at(16, 11, 0, 1))
  phone.tally.handedOut(phone.queue, now: at(16, 11, 0, 8))
  phone.remove(phone.queue, now: at(16, 11, 0, 8))
  check("held by the ledger until the save", phone.context(at(16, 11, 0, 8)).habits[0].today == 4)
  phone.save(snapshot(endingOn: 16, coffee: 4))
  check("then by the snapshot", phone.context(at(16, 11, 0, 9)).habits[0].today == 4)
}

// Undo.
do {
  var phone = Phone(stored: snapshot(endingOn: 16, coffee: 2))
  var watch = Watch()
  watch.take(phone.context(at(16, 12)), now: at(16, 12))

  // Before the iPhone has the log.
  let first = watch.tap(at(16, 12))
  let firstUndo = watch.undoLast()
  check("undone before it left", watch.coffee(at(16, 12, 0, 2)) == 2)
  // The cancel worked: only the undo arrives, and counts for nothing.
  phone.receive(firstUndo, now: at(16, 12, 0, 3))
  check("an undo for a log never received is ignored", phone.queue.isEmpty)
  _ = first

  // Inside the iPhone's hold: the log leaves the queue unwritten.
  let second = watch.tap(at(16, 13))
  phone.receive(second, now: at(16, 13, 0, 1))
  watch.take(phone.context(at(16, 13, 0, 1)), now: at(16, 13, 0, 1))
  let secondUndo = watch.undoLast()
  check("undone on the watch before the iPhone knows", watch.coffee(at(16, 13, 0, 3)) == 2)
  phone.receive(secondUndo, now: at(16, 13, 0, 4))
  check("dropped from the queue", phone.queue.isEmpty)
  watch.take(phone.context(at(16, 13, 0, 4)), now: at(16, 13, 0, 4))
  check("and from the total", watch.coffee(at(16, 13, 0, 5)) == 2, "\(String(describing: watch.coffee(at(16, 13, 0, 5))))")

  // After the app wrote it: the delete waits in the queue, then is done.
  let third = watch.tap(at(16, 14))
  phone.receive(third, now: at(16, 14, 0, 1))
  phone.tally.handedOut(phone.queue, now: at(16, 14, 0, 7))
  phone.save(snapshot(endingOn: 16, coffee: 3))
  phone.remove(phone.queue, now: at(16, 14, 0, 7))
  watch.take(phone.context(at(16, 14, 0, 7)), now: at(16, 14, 0, 7))
  check("written", watch.coffee(at(16, 14, 0, 7)) == 3)
  phone.receive(watch.undoLast(), now: at(16, 14, 0, 7).addingTimeInterval(0.5))
  check("a late undo queues a delete", phone.queue.map(\.op) == [.delete])
  watch.take(phone.context(at(16, 14, 0, 8)), now: at(16, 14, 0, 8))
  check("the delete already counts", watch.coffee(at(16, 14, 0, 8)) == 2, "\(String(describing: watch.coffee(at(16, 14, 0, 8))))")
  // Headless: deleted with no snapshot saved.
  phone.remove(phone.queue, now: at(16, 14, 0, 20))
  check("deleted with the app closed", phone.context(at(16, 14, 0, 20)).habits[0].today == 2)
  phone.save(snapshot(endingOn: 16, coffee: 2))
  check("and after the app opens", phone.context(at(16, 14, 1)).habits[0].today == 2)
}

// A log and its own delete, both dropped unwritten, change nothing.
do {
  let log = QueuedLog(op: .log, id: "a", uid: "u1", viceID: "coffee", createdAt: at(16, 9).timeIntervalSince1970 * 1000)
  let delete = QueuedLog(op: .delete, id: "a", uid: "u1", viceID: "coffee", createdAt: log.createdAt)
  check("a cancelled pair", WatchLedgerEntry.written([log, delete], reflected: []).isEmpty)
  var tally = WatchTally()
  tally.handedOut([log, delete], now: at(16, 10))
  check("is never being written", tally.flushing.isEmpty)
  let both = WatchContext.build(
    snapshot: snapshot(endingOn: 16, coffee: 2), queue: [log, delete], tally: tally, received: [], now: at(16, 10),
    calendar: calendar)
  check("and counts nothing", both.habits[0].today == 2)
}

// What the watch is told, and what it shows of it.
do {
  let context = Phone(stored: snapshot(endingOn: 16, coffee: 2)).context(at(16, 10))
  check("the top habits in the app's order", context.habits.map(\.id) == ["coffee", "wine"])
  check("with their marks", context.habits.map(\.style) == ["filled", "ring"])
  check("survives the transfer", WatchContext(dictionary: context.dictionary) == context)

  let nobody = Phone(stored: nil).context(at(16, 10))
  check("signed out says so", nobody.uid == nil && nobody.habits.isEmpty)
  check("and the watch shows nothing", WatchBoard(context: nobody, outbox: [], now: at(16, 10), calendar: calendar).state == .signedOut)
  check("no context yet", WatchBoard(context: nil, outbox: [], now: at(16, 10), calendar: calendar).state == .noData)

  // Another account signs in on the iPhone: the first one's logs count for nothing here.
  var watch = Watch()
  watch.take(context, now: at(16, 10))
  _ = watch.tap(at(16, 10))
  let other = Phone(stored: snapshot(endingOn: 16, coffee: 7, uid: "u2")).context(at(16, 10, 1))
  watch.take(other, now: at(16, 10, 1))
  check("another account's total is its own", watch.coffee(at(16, 10, 1)) == 7)
  check("and the outbox forgets the first", watch.outbox.isEmpty)

  var waiting = Watch()
  waiting.take(context, now: at(16, 10))
  _ = waiting.tap(at(16, 10))
  let soon = WatchBoard(context: waiting.context, outbox: waiting.outbox, now: at(16, 10, 0, 5), calendar: calendar)
  let later = WatchBoard(context: waiting.context, outbox: waiting.outbox, now: at(16, 10, 1), calendar: calendar)
  check("a transfer gets a moment", soon.waiting == 0)
  check("then the log is waiting", later.waiting == 1)
}

// Only a well-formed message is taken.
do {
  let good: [String: Any] = ["op": "log", "id": "abcdefghij0123456789", "uid": "u1", "viceID": "coffee", "at": 1.0e12]
  check("a message parses", WatchMessage(dictionary: good) != nil)
  for (key, value) in [("op", "write"), ("id", "short"), ("id", "abcdefghij012345678/"), ("uid", ""), ("viceID", "a/b")] {
    var bad = good
    bad[key] = value
    check("a bad \(key) is refused", WatchMessage(dictionary: bad) == nil, value)
  }
}

if failures > 0 {
  print("\(failures) failed")
  exit(1)
}
print("watch model: ok")
