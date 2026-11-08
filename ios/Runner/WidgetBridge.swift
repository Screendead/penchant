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

  @discardableResult
  static func register(with registrar: FlutterPluginRegistrar) -> FlutterMethodChannel {
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
        // After the reply: ending the task destroys the engine that called.
        #if os(iOS)
          let outcome = call.arguments as? String
          DispatchQueue.main.async { BackgroundFlush.finish(outcome: outcome) }
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

  static func start(_ appChannel: FlutterMethodChannel) {
    let first = channel == nil
    channel = appChannel
    guard first else { return }
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), nil,
      { _, _, _, _, _ in DispatchQueue.main.async { QueueListener.flush() } },
      queueChangedNotification as CFString, nil, .deliverImmediately)
    #if os(macOS)
      MacFlushSchedule.update()
    #endif
  }

  static var running: Bool { channel != nil }

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

#if os(macOS)
  // A widget click while the app runs reaches it through QueueListener. This
  // only retries a flush that left the user's logs queued (the key not yet
  // loaded, say), every 15 minutes or more at utility priority, and stops once
  // the queue is empty. With the app closed, the logs wait for its launch.
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
    // Under the about 30 s iOS gives a refresh, so a run ends on its own.
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
      LogQueue.flushInThisProcess = { DispatchQueue.main.async { soon() } }
    }

    // A log intent just changed the queue in this process.
    private static func soon() {
      let assertion = Assertion()
      guard assertion.begin(onExpiry: { stop() }) else { return }
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
          stop()
          complete(true)
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
      let remaining = UIApplication.shared.backgroundTimeRemaining - 3
      DispatchQueue.main.asyncAfter(deadline: .now() + min(budget, max(remaining, 1))) { [token = runToken] in
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
        WidgetBridge.register(with: registrar)
      }
      engine = headless
    }

    // backgroundDone from the headless engine: BackgroundFlushOutcome's name.
    static func finish(outcome: String?) {
      end(retry: outcome != "blocked")
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
    // own, unless the run was blocked (signed out, the key needs recovery).
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
      if retry && left {
        start()
      } else {
        running = true
        end(retry: false)
      }
    }
  }

  // One UIApplication background task, ended once whichever comes first.
  private final class Assertion {
    private var id = UIBackgroundTaskIdentifier.invalid

    var active: Bool { id != .invalid }

    func begin(onExpiry: @escaping () -> Void) -> Bool {
      id = UIApplication.shared.beginBackgroundTask(withName: LogQueue.refreshTaskID) { [self] in
        onExpiry()
        end()
      }
      return active
    }

    func end() {
      guard active else { return }
      let ended = id
      id = .invalid
      UIApplication.shared.endBackgroundTask(ended)
    }
  }
#endif
