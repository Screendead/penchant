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
        let outcome = call.arguments as? String
        #if os(iOS)
          DispatchQueue.main.async { BackgroundFlush.finish(outcome: outcome) }
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
  // flush ends. The helper launches it only while no Penchant runs, and the
  // user's own launch meanwhile reaches this process as a reopen
  // (AppDelegate), so no second process opens the Firestore cache.
  enum FlushMode {
    // A sandboxed launcher's arguments are dropped (NSWorkspace.OpenConfiguration
    // .arguments), so the helper leaves this stamp in the App Group first. Only
    // a fresh one counts: a stale stamp must not hide a launch the user made.
    static let argument = "--background-flush"
    private static let stampFreshFor: TimeInterval = 10
    // Session and key within 12 s, a write within 10 s more (backgroundReadyWithin).
    private static let budget: TimeInterval = 25

    static private(set) var active: Bool = launchedToFlush()
    private static var engine: FlutterEngine?
    private static var startedAt = Date()

    private static func launchedToFlush() -> Bool {
      if CommandLine.arguments.contains(argument) { return true }
      guard let defaults = UserDefaults(suiteName: appGroup) else { return false }
      let stamp = defaults.double(forKey: FlushModeStamp.key)
      guard stamp > 0 else { return false }
      defaults.removeObject(forKey: FlushModeStamp.key)
      return abs(Date().timeIntervalSince1970 - stamp) < stampFreshFor
    }

    static func start() {
      startedAt = Date()
      DispatchQueue.main.asyncAfter(deadline: .now() + budget) {
        if active { quit() }
      }
      run()
    }

    private static func run() {
      guard active else { return }
      if LogQueue.pending().isEmpty {
        quit()
        return
      }
      let headless = FlutterEngine(name: "background-flush", project: nil, allowHeadlessExecution: true)
      RegisterGeneratedPlugins(registry: headless)
      WidgetBridge.register(with: headless.registrar(forPlugin: "WidgetBridge"))
      engine = headless
      if !headless.run(withEntrypoint: "backgroundFlushMain") {
        quit()
      }
    }

    // backgroundDone: BackgroundFlushOutcome's name. A log still inside its
    // Undo hold gets one more run, if it falls due within the budget; anything
    // else left waits for the helper's next launch or the app's.
    static func finish(outcome: String?) {
      guard active else { return }
      stopEngine()
      let due = LogQueue.pending().map { $0.date.addingTimeInterval(queuedLogHold) }.max()
      if outcome == "retry", let due, due > Date(),
        due.timeIntervalSince(startedAt) < budget - 15
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + due.timeIntervalSinceNow + 0.5) { run() }
        return
      }
      quit()
    }

    // The user opened Penchant while it flushed: the app's own flush
    // (widgetLogFlushProvider) writes what is left, to the same document ids.
    static func leave() {
      active = false
      stopEngine()
    }

    private static func stopEngine() {
      engine?.shutDownEngine()
      engine = nil
    }

    private static func quit() {
      stopEngine()
      NSApp.terminate(nil)
    }
  }
#else
  // A BGAppRefreshTask, asked for by LogQueue.scheduleRefresh only while the
  // queue holds the user's logs. A suspended app's own engine flushes; a
  // launch into the background has no engine (the implicit one comes with a
  // scene), so a headless one runs backgroundFlushMain in lib/main.dart, which
  // writes through the same TrackerWrites, sealed, or leaves the logs queued.
  // Firebase's native instances are per process, so both engines share them.
  enum BackgroundFlush {
    // Under the about 30 s iOS gives a refresh, so the task ends on its own.
    private static let budget: TimeInterval = 25

    private static var task: BGTask?
    private static var engine: FlutterEngine?

    // Before application(_:didFinishLaunchingWithOptions:) returns, once.
    static func register() {
      let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: LogQueue.refreshTaskID, using: .main) {
        run($0)
      }
      if !registered {
        NSLog("Penchant: %@ is missing from BGTaskSchedulerPermittedIdentifiers", LogQueue.refreshTaskID)
      }
      NotificationCenter.default.addObserver(
        forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
      ) { _ in LogQueue.scheduleRefresh() }
    }

    private static func run(_ bgTask: BGTask) {
      guard task == nil else {
        bgTask.setTaskCompleted(success: false)
        return
      }
      task = bgTask
      bgTask.expirationHandler = { DispatchQueue.main.async { end(retry: true) } }
      DispatchQueue.main.asyncAfter(deadline: .now() + budget) { [weak bgTask] in
        if let bgTask, bgTask === task { end(retry: true) }
      }
      if LogQueue.pending().isEmpty {
        end(retry: false)
      } else if QueueListener.running {
        QueueListener.flush { canFlush in end(retry: canFlush) }
      } else {
        startHeadless()
      }
    }

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

    // A log still queued (held back, the key not in time, the task expired
    // mid-write) gets another refresh; the next flush writes the same
    // document id, so nothing doubles.
    private static func end(retry: Bool) {
      guard let current = task else { return }
      task = nil
      engine?.destroyContext()
      engine = nil
      let left = !LogQueue.pending().isEmpty
      if retry && left {
        LogQueue.scheduleRefresh()
      }
      current.setTaskCompleted(success: !left)
    }
  }
#endif
