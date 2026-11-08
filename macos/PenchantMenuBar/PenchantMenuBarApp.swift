import AppKit
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
    MenuBarExtra {
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
  private var timer: Timer?

  func refresh() {
    snapshot = Snapshot.load()
    last = LastLog.load().flatMap { $0.undoUntil > Date() ? $0 : nil }
    appRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty
    pending = LogQueue.pending().count
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

  // The login item stays registered, so it is back at the next login or
  // the app's next launch.
  func quit() {
    NSApp.terminate(nil)
  }
}

struct MenuContent: View {
  @ObservedObject var model: MenuModel

  static let signedOut = "Sign in to Penchant to log from here."
  static let noHabits = "No habits yet. Add one in Penchant."

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
        Button("Quit") { model.quit() }
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
      Text("Saved — syncs shortly").font(Typeface.text(12)).foregroundStyle(Palette.muted)
    }
  }
}

// A log queued with Penchant closed (here or in a widget, which posts the same
// Darwin notification) launches Penchant once it is past its Undo hold, with
// no window or Dock icon, to write it (FlushMode in ios/Runner/WidgetBridge.swift).
// Nothing runs while the queue is empty, and nothing polls: a log that run
// could not write (signed out, no key, offline) waits for the next log or the
// app's own launch.
enum FlushLauncher {
  private static var due: DispatchWorkItem?
  private static var launching = false
  private static var lastLaunch = Date.distantPast

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
    // A log made while that run was flushing, after it read the queue.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
    ) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard app?.bundleIdentifier == mainAppID else { return }
      if LogQueue.pending().contains(where: { $0.date > lastLaunch }) { schedule() }
    }
    schedule()
  }

  static func schedule() {
    due?.cancel()
    due = nil
    let logs = LogQueue.pending()
    guard let held = logs.map({ $0.date.addingTimeInterval(queuedLogHold) }).max() else { return }
    let work = DispatchWorkItem { launch() }
    due = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(held.timeIntervalSinceNow, 0) + 0.5, execute: work)
  }

  private static func launch() {
    due = nil
    guard !launching, !LogQueue.pending().isEmpty,
      NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty,
      let url = appURL, let defaults = UserDefaults(suiteName: appGroup)
    else { return }
    launching = true
    lastLaunch = Date()
    defaults.set(Date().timeIntervalSince1970, forKey: FlushModeStamp.key)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      DispatchQueue.main.async {
        launching = false
        if error != nil { defaults.removeObject(forKey: FlushModeStamp.key) }
      }
    }
  }
}
