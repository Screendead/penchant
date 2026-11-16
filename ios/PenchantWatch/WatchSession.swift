import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

// The watch app's state: the iPhone's context, the logs made here, and the
// WCSession that carries both. A log is handed to transferUserInfo at the tap,
// which queues it and delivers it even if the app ends; the iPhone writes it
// (ios/Runner/WatchLink.swift).
@MainActor
final class WatchJournal: NSObject, ObservableObject {
  @Published private(set) var board = WatchBoard(context: nil, outbox: [], now: Date())
  // The log Undo is offered for, until its window ends.
  @Published private(set) var last: WatchLog?
  // The habit a complication opened the app on.
  @Published var focus: String?

  private var transfers: [String: WCSessionUserInfoTransfer] = [:]
  private var live = true
  private var started = false

  // From the scene, or from a background wake that came before any scene.
  func start() {
    guard !started else { return }
    started = true
    #if DEBUG
      if let demo = WatchDemo.requested {
        live = false
        demo.apply()
        refresh()
        if demo == .logged, let row = board.rows.first {
          log(row.habit)
        }
      }
    #endif
    refresh()
    guard live, WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  // Rereads the store and drops what no longer matters; the day may have
  // changed since the last look.
  func refresh(now: Date = Date()) {
    let context = WatchStore.context
    let kept = WatchLog.pruned(WatchStore.outbox, context: context, now: now)
    if kept != WatchStore.outbox {
      WatchStore.outbox = kept
    }
    board = WatchBoard(context: context, outbox: kept, now: now)
    if let shown = last, now >= shown.undoUntil || !kept.contains(where: { $0.id == shown.id }) {
      last = nil
    }
  }

  func log(_ habit: WatchContext.Habit, now: Date = Date()) {
    guard let uid = WatchStore.context?.uid else { return }
    let log = WatchLog(uid: uid, viceID: habit.id, at: now)
    WatchStore.outbox.append(log)
    last = log
    focus = nil
    WKInterfaceDevice.current().play(.success)
    hand()
    changed()
  }

  func undo(now: Date = Date()) {
    guard let shown = last, now < shown.undoUntil else { return }
    var outbox = WatchStore.outbox
    guard let i = outbox.firstIndex(where: { $0.id == shown.id }) else { return }
    outbox[i].undone = true
    WatchStore.outbox = outbox
    // The cancel stops a transfer still waiting; one already on its way is
    // followed by the undo, which the iPhone ignores for a log it never got.
    if let transfer = transfers.removeValue(forKey: shown.id), transfer.isTransferring {
      transfer.cancel()
    }
    last = nil
    WKInterfaceDevice.current().play(.click)
    hand()
    changed()
  }

  // Gives WCSession whatever it has not had: transferUserInfo is an error
  // before the session activates, so a tap at launch waits for that.
  private func hand() {
    guard live, WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
    var outbox = WatchStore.outbox
    for i in outbox.indices {
      if !outbox[i].undone && !outbox[i].handed {
        transfers[outbox[i].id] = WCSession.default.transferUserInfo(
          WatchMessage(op: .log, log: outbox[i]).dictionary)
        outbox[i].handed = true
      } else if outbox[i].undone && outbox[i].handed && !outbox[i].undoHanded {
        WCSession.default.transferUserInfo(WatchMessage(op: .undo, log: outbox[i]).dictionary)
        outbox[i].undoHanded = true
      }
    }
    WatchStore.outbox = outbox
  }

  private func changed() {
    refresh()
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func take(_ context: WatchContext) {
    let habits = WatchStore.context?.habits.map(\.id)
    WatchStore.context = context
    if habits != context.habits.map(\.id) {
      WidgetCenter.shared.invalidateConfigurationRecommendations()
    }
    changed()
  }

  // Holds a background wake until the session has delivered what it woke the
  // app for, 5 seconds at most: activation is still under way when the wake
  // starts, and the context arrives after it.
  func settle() async {
    for _ in 0..<50 {
      guard WCSession.default.activationState != .activated || WCSession.default.hasContentPending else { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    // The delegate hands each context to the main actor in a task of its own.
    await Task.yield()
  }
}

extension WatchJournal: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
  ) {
    let context = WatchContext(dictionary: session.receivedApplicationContext)
    Task { @MainActor in
      if let context {
        take(context)
      }
      hand()
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let context = WatchContext(dictionary: applicationContext) else { return }
    Task { @MainActor in take(context) }
  }
}

#if DEBUG
  // `-penchantDemo list|logged|new-day|signed-out|empty` shows made-up habits
  // with no session, for screenshots: the Simulator carries no transfers.
  enum WatchDemo: String {
    case list, logged, newDay = "new-day", signedOut = "signed-out", empty

    static var requested: WatchDemo? {
      let arguments = ProcessInfo.processInfo.arguments
      guard let flag = arguments.firstIndex(of: "-penchantDemo"), arguments.indices.contains(flag + 1) else {
        return nil
      }
      return WatchDemo(rawValue: arguments[flag + 1])
    }

    @MainActor func apply() {
      let now = Date()
      let today = WatchDay.key(now)
      let habits = [
        ("coffee", "Coffee", "cup", "cups", 0, "filled", 3.0), ("wine", "Wine", "glass", "glasses", 1, "filled", 0.0),
        ("cigarettes", "Cigarettes", "cigarette", "cigarettes", 2, "filled", 6.0),
        ("snacks", "Late snacks", "snack", "snacks", 3, "filled", 1.0),
        ("cola", "Cola", "can", "cans", 0, "ring", 2.0),
      ].map {
        WatchContext.Habit(
          id: $0.0, name: $0.1, unitOne: $0.2, unitOther: $0.3, slot: $0.4, style: $0.5, today: $0.6)
      }
      WatchStore.outbox = []
      switch self {
      case .empty:
        WatchStore.context = nil
      case .signedOut:
        WatchStore.context = .signedOut(day: today)
      case .list, .logged:
        WatchStore.context = WatchContext(uid: "demo", day: today, habits: habits, received: [])
      case .newDay:
        WatchStore.context = WatchContext(
          uid: "demo", day: WatchDay.key(now.addingTimeInterval(-86400)), habits: habits, received: [])
      }
    }
  }
#endif
