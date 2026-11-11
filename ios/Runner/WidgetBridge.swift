import AppIntents
import WidgetKit

#if os(macOS)
  import FlutterMacOS
#else
  import BackgroundTasks
  import Flutter
#endif

// The Dart side is lib/widget_bridge/widget_bridge.dart; the widgets read the
// snapshot in ios/PenchantWidgets/Snapshot.swift and leave logs in
// ios/PenchantWidgets/LogQueue.swift. The macOS app compiles this file too.
enum WidgetBridge {
  static let channelName = "com.screendead.penchant/widgets"

  // onBackgroundDone hears the headless engine's backgroundDone, on the main
  // queue after the reply: ending the run destroys the engine that called.
  @discardableResult
  static func register(
    with registrar: FlutterPluginRegistrar, onBackgroundDone: ((_ outcome: String?) -> Void)? = nil
  ) -> FlutterMethodChannel {
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let defaults = UserDefaults(suiteName: appGroup) else {
        result(FlutterError(code: "no-app-group", message: "App Group \(appGroup) is unavailable", details: nil))
        return
      }
      switch call.method {
      case "save":
        guard let snapshot = call.arguments as? String else {
          result(FlutterError(code: "bad-arguments", message: "save takes the snapshot as a string", details: nil))
          return
        }
        defaults.set(snapshot, forKey: snapshotKey)
        if #available(iOS 17.0, macOS 14.0, *) {
          PenchantShortcuts.updateAppShortcutParameters()
        }
      case "clear":
        defaults.removeObject(forKey: snapshotKey)
        LastLog.save(nil)
      case "pendingLogs":
        let data = (try? JSONEncoder().encode(LogQueue.read())) ?? Data("[]".utf8)
        result(String(decoding: data, as: UTF8.self))
        return
      case "backgroundDone":
        result(nil)
        // After the reply: ending the run destroys the engine that called.
        let outcome = call.arguments as? String
        #if os(iOS)
          if let onBackgroundDone {
            DispatchQueue.main.async { onBackgroundDone(outcome) }
          }
        #else
          DispatchQueue.main.async { FlushMode.finish(outcome: outcome) }
        #endif
        return
      case "removeLogs":
        guard let json = call.arguments as? String,
          let done = try? JSONDecoder().decode([QueuedLog].self, from: Data(json.utf8))
        else {
          result(FlutterError(code: "bad-arguments", message: "removeLogs takes the logs as JSON", details: nil))
          return
        }
        guard LogQueue.remove(done) else {
          result(FlutterError(code: "queue-unwritable", message: "Could not update the log queue", details: nil))
          return
        }
        // On to the reload: the snapshot may already count these entries,
        // and no later save follows if the acknowledgement changes nothing.
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      WidgetCenter.shared.reloadAllTimelines()
      result(nil)
    }
    return channel
  }
}

// Asks the app's running Dart to flush the queue (widgetLogFlushProvider in
// lib/widget_bridge/log_queue.dart) whenever another process queues a log.
// Dart answers not implemented while it cannot flush (signed out, no key).
enum QueueListener {
  private static var channel: FlutterMethodChannel?
  private static var observing = false

  static func start(_ appChannel: FlutterMethodChannel) {
    channel = appChannel
    guard !observing else { return }
    observing = true
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), nil,
      { _, _, _, _, _ in DispatchQueue.main.async { QueueListener.flush() } },
      queueChangedNotification as CFString, nil, .deliverImmediately)
    #if os(macOS)
      MacFlushSchedule.update()
    #endif
  }

  static var running: Bool { channel != nil }

  #if os(iOS)
    // A released engine's channel never replies ("Communicating on a dead
    // channel." in FlutterBinaryMessengerRelay.mm), so the listener forgets
    // it when the engine deallocates, and BackgroundFlush starts a headless
    // engine instead. The implicit engine belongs to the scene's view
    // controller, which iOS may release while the process stays alive.
    static func start(_ appChannel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
      start(appChannel)
      registrar.publish(EngineGone { if channel === appChannel { channel = nil } })
    }

    // FlutterEngine's dealloc calls detachFromEngine on each published value.
    private final class EngineGone: NSObject, FlutterPlugin {
      private let gone: () -> Void

      init(_ gone: @escaping () -> Void) {
        self.gone = gone
      }

      static func register(with registrar: FlutterPluginRegistrar) {}

      func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        DispatchQueue.main.async(execute: gone)
      }
    }
  #endif

  // Calls back on the main queue once Dart's flush has ended, or at once
  // without a Dart to ask. canFlush is false when Dart could not.
  static func flush(then done: ((_ canFlush: Bool) -> Void)? = nil) {
    guard let channel else {
      done?(false)
      return
    }
    channel.invokeMethod("flush", arguments: nil) { reply in
      let canFlush = !(reply is FlutterError) && (reply as AnyObject?) !== FlutterMethodNotImplemented
      #if os(macOS)
        MacFlushSchedule.update()
      #endif
      done?(canFlush)
    }
  }
}

// A widget's or the menu bar's "What was going on?" (EntryLink in
// ios/PenchantWidgets/LogQueue.swift) reaches Dart here, as ids: the app
// writes the queued log, then asks (lib/widget_bridge/entry_prompt.dart).
// Only the last log counts: an Undo clears it, so an undone entry is never
// handed over, and it is offered once.
enum EntryPrompt {
  static let channelName = "com.screendead.penchant/entry_prompt"
  private static var channel: FlutterMethodChannel?
  // Kept until Dart takes it: a launch's URL arrives before the engine runs.
  private static var pending: LastLog?

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let appChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    appChannel.setMethodCallHandler { call, result in
      guard call.method == "take" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let taken = pending else {
        result(nil)
        return
      }
      pending = nil
      result(["id": taken.id, "viceID": taken.viceID])
    }
    channel = appChannel
  }

  // Whether the URL was an EntryLink; it is handled whether or not it names
  // the last log.
  @discardableResult
  static func open(_ url: URL) -> Bool {
    guard let id = EntryLink.activityID(url) else { return false }
    guard var last = LastLog.load(), last.id == id, last.asked != true else { return true }
    last.asked = true
    LastLog.save(last)
    WidgetCenter.shared.reloadAllTimelines()
    pending = last
    channel?.invokeMethod("changed", arguments: nil)
    return true
  }
}

#if os(macOS)
  // A widget click while the app runs reaches it through QueueListener. This
  // only retries a flush that left the user's logs queued (the key not yet
  // loaded, say), every 15 minutes or more at utility priority, and stops once
  // the queue is empty. With the app closed, the menu bar helper launches it
  // in FlushMode.
  enum MacFlushSchedule {
    private static var activity: NSBackgroundActivityScheduler?

    static func update() {
      if LogQueue.pending().isEmpty {
        activity?.invalidate()
        activity = nil
        return
      }
      guard activity == nil else { return }
      let scheduler = NSBackgroundActivityScheduler(identifier: "com.screendead.penchant.flush-log-queue")
      scheduler.interval = 15 * 60
      scheduler.tolerance = 5 * 60
      scheduler.qualityOfService = .utility
      scheduler.repeats = true
      scheduler.schedule { completion in
        DispatchQueue.main.async {
          QueueListener.flush { _ in completion(.finished) }
        }
      }
      activity = scheduler
    }
  }

  // Penchant launched by the menu bar helper (macos/PenchantMenuBar) to write
  // what was queued while it was closed: no Dock icon, no window, and a
  // headless engine on backgroundFlushMain in lib/main.dart, which seals and
  // writes through TrackerWrites or leaves the logs queued. It quits once the
  // flush ends, leaving the outcome in the App Group for the helper, which
  // tries again after a retry. The helper launches it only while no Penchant
  // runs, and the user's own launch meanwhile reaches this process as a reopen
  // (AppDelegate), so no second process opens the Firestore cache.
  enum FlushMode {
    // A sandboxed launcher's arguments are dropped (NSWorkspace.OpenConfiguration
    // .arguments), so the helper leaves a stamp in the App Group first. Only a
    // recent one counts: a stale stamp must not hide a launch the user made.
    // It is consumed on read and removed when the launch fails, so the window
    // can be wide enough for a launch slowed by login or a Gatekeeper scan.
    static let argument = "--background-flush"
    private static let stampFreshFor: TimeInterval = 60
    // No system limit applies on the Mac. Engine start and Firebase take a few
    // seconds, the session and key up to 12 s between them
    // (backgroundReadyWithin), and a write 10 s more (writeTimeout).
    private static let budget: TimeInterval = 40
    private static let runNeeds: TimeInterval = 30

    static private(set) var active: Bool = launchedToFlush()
    private static var engine: FlutterEngine?
    private static var startedAt = Date()

    private static func launchedToFlush() -> Bool {
      if CommandLine.arguments.contains(argument) { return true }
      guard let defaults = UserDefaults(suiteName: appGroup) else { return false }
      let stamp = defaults.double(forKey: FlushHandoff.launchedAt)
      guard stamp > 0 else { return false }
      defaults.removeObject(forKey: FlushHandoff.launchedAt)
      return abs(Date().timeIntervalSince1970 - stamp) < stampFreshFor
    }

    static func start() {
      startedAt = Date()
      DispatchQueue.main.asyncAfter(deadline: .now() + budget) {
        if active { quit(outcome: "retry") }
      }
      run()
    }

    private static func run() {
      guard active else { return }
      if LogQueue.pending().isEmpty {
        quit(outcome: "flushed")
        return
      }
      let headless = FlutterEngine(name: "background-flush", project: nil, allowHeadlessExecution: true)
      RegisterGeneratedPlugins(registry: headless)
      WidgetBridge.register(with: headless.registrar(forPlugin: "WidgetBridge"))
      engine = headless
      if !headless.run(withEntrypoint: "backgroundFlushMain") {
        quit(outcome: "retry")
      }
    }

    // backgroundDone: BackgroundFlushOutcome's name. A log still inside its
    // Undo hold gets one more run, if a whole run fits in the budget after it
    // falls due; anything else left is the helper's to retry.
    static func finish(outcome: String?) {
      guard active else { return }
      stopEngine()
      let due = LogQueue.pending().map { $0.date.addingTimeInterval(queuedLogHold) }.max()
      if outcome == "retry", let due, due > Date(),
        due.timeIntervalSince(startedAt) < budget - runNeeds
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + due.timeIntervalSinceNow + 0.5) { run() }
        return
      }
      quit(outcome: outcome ?? "retry")
    }

    // The user opened Penchant while it flushed: the app's own flush
    // (widgetLogFlushProvider) writes what is left, to the same document ids.
    static func leave() {
      active = false
      stopEngine()
      clearOutcome()
    }

    // A normal launch: the helper's retries are for flush-mode runs only.
    static func clearOutcome() {
      UserDefaults(suiteName: appGroup)?.removeObject(forKey: FlushHandoff.outcome)
    }

    private static func stopEngine() {
      engine?.shutDownEngine()
      engine = nil
    }

    private static func quit(outcome: String) {
      stopEngine()
      if let defaults = UserDefaults(suiteName: appGroup) {
        defaults.set(outcome, forKey: FlushHandoff.outcome)
        defaults.synchronize()
      }
      NSApp.terminate(nil)
    }
  }
#else
  // Writes the queue from this process, sealed, through the Dart flush: the
  // running engine's when there is one, otherwise a headless engine on
  // backgroundFlushMain in lib/main.dart (the implicit engine comes with a
  // scene, and a launch into the background has none). Firebase's native
  // instances are per process (cloud_firestore's firestoreInstanceCache), so
  // both engines share one Firestore and one disk cache. Two callers:
  // - a log intent, which iOS runs in this process (LogIntents.swift): soon()
  //   waits out the Undo hold under a UIApplication background task, then
  //   flushes, so a tap reaches Firestore within seconds of the hold;
  // - the BGAppRefreshTask that LogQueue.scheduleRefresh asks for while logs
  //   are queued, the fallback for whatever a tap's run left behind.
  enum BackgroundFlush {
    // Under the about 30 s iOS gives a refresh, so a run ends on its own. A
    // run with less time left is stopped by the expiry handlers.
    private static let budget: TimeInterval = 25

    private static var running = false
    private static var engine: FlutterEngine?
    // Told when the current run ends, with whether a log is still queued.
    private static var waiters: [(_ left: Bool) -> Void] = []
    // Arrived during a run, which may have read the queue before their log.
    private static var next: [(_ left: Bool) -> Void] = []

    // Before application(_:didFinishLaunchingWithOptions:) returns, once.
    static func register() {
      let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: LogQueue.refreshTaskID, using: .main) {
        refresh($0)
      }
      if !registered {
        NSLog("Penchant: %@ is missing from BGTaskSchedulerPermittedIdentifiers", LogQueue.refreshTaskID)
      }
      NotificationCenter.default.addObserver(
        forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
      ) { _ in LogQueue.scheduleRefresh() }
      // On the intent's thread, before perform() returns: UIKit grants the
      // assertion asynchronously, and the app may be suspended soon after.
      LogQueue.flushInThisProcess = {
        let assertion = Assertion()
        guard assertion.begin(onExpiry: { stop() }) else { return }
        DispatchQueue.main.async { soon(assertion) }
      }
    }

    // A log intent just changed the queue in this process.
    private static func soon(_ assertion: Assertion) {
      let wait = LogQueue.due(LogQueue.pending()).timeIntervalSinceNow
      DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait)) {
        guard assertion.active else { return }
        flush { _ in assertion.end() }
      }
    }

    private static func refresh(_ task: BGTask) {
      // A run already in progress covers it, and reschedules if it must.
      guard !running else {
        task.setTaskCompleted(success: false)
        return
      }
      var done = false
      let complete = { (left: Bool) in
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: !left)
      }
      task.expirationHandler = {
        DispatchQueue.main.async {
          complete(true)
          stop()
        }
      }
      flush(then: complete)
    }

    private static func flush(then done: @escaping (_ left: Bool) -> Void) {
      if running {
        next.append(done)
        return
      }
      waiters.append(done)
      start()
    }

    private static func start() {
      running = true
      guard !LogQueue.pending().isEmpty else {
        end(retry: false)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + budget) { [token = runToken] in
        if running && token == runToken { end(retry: true) }
      }
      if QueueListener.running {
        QueueListener.flush { [token = runToken] canFlush in
          if token == runToken { end(retry: canFlush) }
        }
      } else {
        startHeadless()
      }
    }

    private static var runToken = 0

    private static func startHeadless() {
      let headless = FlutterEngine(name: "background-flush", project: nil, allowHeadlessExecution: true)
      guard headless.run(withEntrypoint: "backgroundFlushMain") else {
        end(retry: true)
        return
      }
      GeneratedPluginRegistrant.register(with: headless)
      if let registrar = headless.registrar(forPlugin: "WidgetBridge") {
        // The outcome is BackgroundFlushOutcome's name.
        WidgetBridge.register(with: registrar) { [token = runToken] outcome in
          if token == runToken { end(retry: outcome != "blocked") }
        }
      }
      engine = headless
    }

    // The app is about to be suspended: whatever is left goes to a refresh.
    private static func stop() {
      let late = next
      next = []
      end(retry: true)
      late.forEach { $0(!LogQueue.pending().isEmpty) }
    }

    // A log still queued (held back, the key not in time, the run cut short
    // mid-write) gets a refresh; the next flush writes the same document id,
    // so nothing doubles. Callers that came during the run get one of their
    // own, unless the run was blocked (signed out, the key needs recovery) or
    // every log left is in its hold: each such log's own soon() comes later.
    private static func end(retry: Bool) {
      guard running else { return }
      running = false
      runToken += 1
      engine?.destroyContext()
      engine = nil
      let left = !LogQueue.pending().isEmpty
      if retry && left {
        LogQueue.scheduleRefresh()
      }
      let told = waiters
      waiters = []
      told.forEach { $0(left) }
      guard !next.isEmpty else { return }
      waiters = next
      next = []
      let writable = LogQueue.pending().contains { $0.date.addingTimeInterval(queuedLogHold) <= Date() }
      if retry && left && writable {
        start()
      } else {
        running = true
        end(retry: false)
      }
    }
  }

  // One UIApplication background task, ended once whichever comes first.
  // begin runs on the intent's thread and the rest on the main queue, where
  // UIKit calls the expiry handler, possibly before begin has its identifier
  // (a refused grant), so the lock guards both.
  private final class Assertion: @unchecked Sendable {
    private let lock = NSLock()
    private var id = UIBackgroundTaskIdentifier.invalid
    private var over = false

    var active: Bool { lock.withLock { id != .invalid } }

    func begin(onExpiry: @escaping () -> Void) -> Bool {
      // Ended first, so the teardown in onExpiry never delays suspension.
      let granted = UIApplication.shared.beginBackgroundTask(withName: LogQueue.refreshTaskID) { [self] in
        end()
        DispatchQueue.main.async(execute: onExpiry)
      }
      let expired = lock.withLock {
        if !over { id = granted }
        return over
      }
      if expired && granted != .invalid {
        UIApplication.shared.endBackgroundTask(granted)
      }
      return !expired && granted != .invalid
    }

    func end() {
      let ended = lock.withLock {
        over = true
        defer { id = .invalid }
        return id
      }
      if ended != .invalid {
        UIApplication.shared.endBackgroundTask(ended)
      }
    }
  }
#endif
