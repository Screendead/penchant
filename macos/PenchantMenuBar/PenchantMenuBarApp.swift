import AppKit
import Network
import SwiftUI
import WidgetKit

// A login item inside Penchant.app (Contents/Library/LoginItems), registered by
// the app's AppDelegate, so the menu bar stays when the app quits. It reads the
// snapshot the widgets read and queues logs in the widgets' LogQueue; only the
// app writes to Firestore, sealed. With the app closed, FlushLauncher starts it
// hidden to do so.
let mainAppID = "com.screendead.penchant"

@main
struct PenchantMenuBarApp: App {
  @StateObject private var model = MenuModel()

  init() {
    FlushLauncher.start()
  }

  var body: some Scene {
    MenuBarExtra(isInserted: $model.shown) {
      MenuContent(model: model)
    } label: {
      Image(systemName: "circle.dashed.inset.filled")
        .accessibilityLabel("Penchant")
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class MenuModel: ObservableObject {
  @Published private(set) var snapshot: Snapshot?
  @Published private(set) var last: LastLog?
  @Published private(set) var appRunning = false
  @Published private(set) var pending = 0
  @Published private(set) var failed = false
  @Published private(set) var waiting = FlushLauncher.Waiting.briefly
  @Published var shown = true
  private var timer: Timer?

  init() {
    _ = Staleness.build
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else { return }
        let model = Unmanaged<MenuModel>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async {
          Staleness.exitIfReplaced()
          model.shown = true
        }
      },
      showMenuBarNotification as CFString, nil, .deliverImmediately)
  }

  func refresh() {
    snapshot = Snapshot.load()
    last = LastLog.load().flatMap { $0.undoUntil > Date() ? $0 : nil }
    appRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty
    pending = LogQueue.pending().count
    waiting = FlushLauncher.waiting
  }

  // The snapshot and the queue change in other processes, so the open window
  // polls them; a closed one costs nothing.
  func start() {
    refresh()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func log(_ habit: Snapshot.Habit) {
    guard let uid = snapshot?.uid, let queued = LogQueue.log(uid: uid, viceID: habit.id) else {
      failed = true
      return
    }
    failed = false
    LastLog.save(LastLog(id: queued.id, viceID: habit.id, at: queued.createdAt))
    WidgetCenter.shared.reloadAllTimelines()
    refresh()
  }

  func undo() {
    guard let last, let uid = snapshot?.uid else { return }
    if LogQueue.undo(last, uid: uid) {
      LastLog.save(nil)
    }
    WidgetCenter.shared.reloadAllTimelines()
    refresh()
  }

  func openApp() {
    guard let url = FlushLauncher.appURL else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
  }

  // Hides the item but keeps the process, so FlushLauncher goes on writing
  // what the widgets queue. It is back at the next login or the app's next
  // launch.
  func hide() {
    shown = false
  }
}

struct MenuContent: View {
  @ObservedObject var model: MenuModel

  static let signedOut = "Sign in to Penchant to log from here."
  static let noHabits = "No habits yet. Add one in Penchant."

  static func waiting(_ waiting: FlushLauncher.Waiting) -> String {
    switch waiting {
    case .briefly: "Saved — syncs shortly"
    case .stalled: "Saved — syncs when Penchant opens"
    case .forApp: "Saved — open Penchant to sync"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Today")
        .font(Typeface.display(20))
        .foregroundStyle(Palette.text)
      if let snapshot = model.snapshot, snapshot.uid != nil {
        habits(snapshot)
      } else {
        Text(Self.signedOut).font(Typeface.text(13)).foregroundStyle(Palette.muted)
      }
      status
      Divider()
      HStack {
        Button("Open Penchant") { model.openApp() }
        Spacer()
        Button("Quit") { model.hide() }
          .help("Hides the menu bar item until you next log in or open Penchant.")
      }
      .buttonStyle(.borderless)
      .font(Typeface.text(13, .medium))
    }
    .padding(14)
    .frame(width: 300)
    .background(Palette.bg)
    .onAppear { model.start() }
    .onDisappear { model.stop() }
  }

  @ViewBuilder
  private func habits(_ snapshot: Snapshot) -> some View {
    let shown = snapshot.shown([], count: .max)
    if shown.isEmpty {
      Text(Self.noHabits).font(Typeface.text(13)).foregroundStyle(Palette.muted)
    } else {
      let week = Week(snapshot: snapshot, endingOn: Date())
      VStack(spacing: 6) {
        ForEach(shown) { habit in
          row(habit, today: week.habits.first { $0.id == habit.id }?.values.last ?? nil)
        }
      }
    }
  }

  private func row(_ habit: Snapshot.Habit, today: Double?) -> some View {
    let count = today ?? 0
    return Button {
      model.log(habit)
    } label: {
      HStack(spacing: 10) {
        Circle().fill(Palette.fill(habit.slot)).frame(width: 10, height: 10)
        Text(habit.name).font(Typeface.text(14, .medium)).foregroundStyle(Palette.text)
          .lineLimit(1)
        Spacer()
        Text("\(formatCount(count)) \(habit.unit(count))")
          .font(Typeface.mono(13)).foregroundStyle(Palette.ink(habit.slot))
        Text("+1").font(Typeface.mono(13, .bold)).foregroundStyle(Palette.muted)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Log 1 \(habit.unitOne) of \(habit.name). \(formatCount(count)) today.")
  }

  @ViewBuilder
  private var status: some View {
    if model.failed {
      Text("Penchant could not save that. Try again in the app.")
        .font(Typeface.text(12)).foregroundStyle(Palette.muted)
    } else if let last = model.last, let habit = model.snapshot?.habit(last.viceID) {
      HStack {
        Text("Logged 1 \(habit.unitOne) of \(habit.name)").font(Typeface.text(12)).foregroundStyle(Palette.muted)
          .lineLimit(1)
        Spacer()
        Button("Undo") { model.undo() }.buttonStyle(.borderless).font(Typeface.text(12, .bold))
      }
    } else if model.pending > 0 && !model.appRunning {
      Text(Self.waiting(model.waiting)).font(Typeface.text(12)).foregroundStyle(Palette.muted)
    }
  }
}

// Installing or updating Penchant replaces the bundle under a running helper,
// and the app's registration leaves that process running the old code from
// wherever the old bundle went, the Trash included. Penchant
// posts showMenuBarNotification at each launch; a helper whose bundle on disk
// is gone or another build then exits, and the app opens its own helper.
enum Staleness {
  static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

  static func exitIfReplaced() {
    let info = NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))
    guard info?["CFBundleVersion"] as? String != build else { return }
    exit(0)
  }
}

// A log queued with Penchant closed (here or in a widget, which posts the same
// Darwin notification) launches Penchant once it is past its Undo hold, with
// no window or Dock icon, to write it (FlushMode in ios/Runner/WidgetBridge.swift).
// Nothing runs while the queue is empty. A run that leaves logs for a retry
// (offline, or the session or key slow to load) is tried again when the
// network comes back, when the Mac wakes, and on a backoff that gives up after
// about an hour; one that needs the app (the key needs recovery, a refused
// log) waits for it, or for the next log.
enum FlushLauncher {
  enum Waiting { case briefly, stalled, forApp }

  private static var due: DispatchWorkItem?
  private static var launching = false
  private static var lastLaunch = Date.distantPast
  private static var retries = 0
  private static var backoff: NSBackgroundActivityScheduler?
  private static let backoffMinutes: [Double] = [1, 4, 15, 40]
  private static let path = NWPathMonitor()
  private static var online: Bool?

  static private(set) var waiting = Waiting.briefly

  // The app this helper is bundled in, so a copy elsewhere drives its own app.
  static var appURL: URL? {
    let enclosing = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    if Bundle(url: enclosing)?.bundleIdentifier == mainAppID { return enclosing }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainAppID)
  }

  static func start() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), nil,
      { _, _, _, _, _ in DispatchQueue.main.async { FlushLauncher.schedule() } },
      queueChangedNotification as CFString, nil, .deliverImmediately)
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard app?.bundleIdentifier == mainAppID else { return }
      ended()
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in retryNow() }
    // A trigger only: launches never wait on it, so a monitor that misreports
    // in the sandbox costs this trigger and nothing else.
    path.pathUpdateHandler = { update in
      DispatchQueue.main.async {
        let nowOnline = update.status == .satisfied
        defer { online = nowOnline }
        if nowOnline && online == false { retryNow() }
      }
    }
    path.start(queue: .main)
    schedule()
  }

  // A new log: its own launch, once past its hold.
  static func schedule() {
    due?.cancel()
    due = nil
    let logs = LogQueue.pending()
    guard let held = logs.map({ $0.date.addingTimeInterval(queuedLogHold) }).max() else {
      settle(.briefly)
      return
    }
    backoff?.invalidate()
    backoff = nil
    waiting = .briefly
    let work = DispatchWorkItem { launch() }
    due = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(held.timeIntervalSinceNow, 0) + 0.5, execute: work)
  }

  // The network back, or the Mac awake: a run that left logs for a retry
  // gets one now, and the backoff starts over.
  private static func retryNow() {
    guard waiting == .stalled || backoff != nil else { return }
    retries = 0
    schedule()
  }

  // Penchant quit, after a flush-mode run or the user's own session.
  private static func ended() {
    let logs = LogQueue.pending()
    guard !logs.isEmpty else {
      settle(.briefly)
      return
    }
    // A log made while that run was flushing, after it read the queue.
    if logs.contains(where: { $0.date > lastLaunch }) {
      schedule()
      return
    }
    switch UserDefaults(suiteName: appGroup)?.string(forKey: FlushHandoff.outcome) {
    case "retry", "flushed":
      retryLater()
    default:
      // Blocked, or the user's own session (it leaves no outcome) ended with
      // logs it could not write.
      settle(.forApp)
    }
  }

  private static func retryLater() {
    backoff?.invalidate()
    backoff = nil
    guard retries < backoffMinutes.count else {
      waiting = .stalled
      return
    }
    waiting = .briefly
    let minutes = backoffMinutes[retries]
    retries += 1
    // Repeating, so its first run comes about one interval from now rather
    // than at any point within it; it runs once.
    let scheduler = NSBackgroundActivityScheduler(identifier: "com.screendead.penchant.menubar.retry-flush")
    scheduler.interval = minutes * 60
    scheduler.tolerance = minutes * 15
    scheduler.qualityOfService = .utility
    scheduler.repeats = true
    scheduler.schedule { completion in
      DispatchQueue.main.async {
        backoff?.invalidate()
        backoff = nil
        launch()
      }
      completion(.finished)
    }
    backoff = scheduler
  }

  private static func settle(_ state: Waiting) {
    backoff?.invalidate()
    backoff = nil
    retries = 0
    waiting = state
  }

  private static func launch() {
    due = nil
    guard !launching, !LogQueue.pending().isEmpty,
      NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty,
      let url = appURL, let defaults = UserDefaults(suiteName: appGroup)
    else { return }
    launching = true
    lastLaunch = Date()
    defaults.removeObject(forKey: FlushHandoff.outcome)
    defaults.set(Date().timeIntervalSince1970, forKey: FlushHandoff.launchedAt)
    // The new process reads it before its window loads; a stamp it misses
    // makes the launch a normal, focused one.
    defaults.synchronize()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      DispatchQueue.main.async {
        launching = false
        if error != nil { defaults.removeObject(forKey: FlushHandoff.launchedAt) }
      }
    }
  }
}
