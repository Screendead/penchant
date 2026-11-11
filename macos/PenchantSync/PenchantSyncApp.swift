import Cocoa
import FlutterMacOS

// Penchant's background sync, at Contents/Library/LoginItems/PenchantSync.app
// inside Penchant.app. The menu bar helper launches it to write what the
// widgets queued while Penchant is closed. LSBackgroundOnly and a prohibited
// activation policy: no window, Dock icon or menu bar, and nothing can
// activate it. It runs Penchant's own Dart (the enclosing app's
// App.framework) headless on backgroundFlushMain in lib/main.dart, which
// seals and writes through TrackerWrites, and quits once the flush ends,
// leaving the outcome in the App Group (FlushHandoff.outcome) for the helper.
// Its keychain access group is the app's first, so Firebase Auth's session
// and the journal key are the app's; its sandbox container, and so its
// Firestore cache, is its own.
@main
final class SyncDelegate: NSObject, NSApplicationDelegate {
  static func main() {
    let app = NSApplication.shared
    let delegate = SyncDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.prohibited)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    SyncRun.start()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    .terminateNow
  }
}

enum SyncRun {
  // No system limit applies on the Mac. Engine start and Firebase take a few
  // seconds, the session and key up to 12 s between them
  // (backgroundReadyWithin), and a write 10 s more (writeTimeout).
  private static let budget: TimeInterval = 40
  private static let runNeeds: TimeInterval = 30

  private static var engine: FlutterEngine?
  private static var startedAt = Date()
  private static var ended = false

  // Contents/Library/LoginItems/PenchantSync.app, four levels down.
  static var enclosingApp: URL {
    Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  static func start() {
    startedAt = Date()
    DispatchQueue.main.asyncAfter(deadline: .now() + budget) { quit(outcome: "retry") }
    run()
  }

  private static func run() {
    guard !ended else { return }
    if LogQueue.pending().isEmpty {
      quit(outcome: "flushed")
      return
    }
    let dart = Bundle(url: enclosingApp.appendingPathComponent("Contents/Frameworks/App.framework"))
    let project = FlutterDartProject(precompiledDartBundle: dart)
    let headless = FlutterEngine(name: "background-flush", project: project, allowHeadlessExecution: true)
    RegisterGeneratedPlugins(registry: headless)
    WidgetBridge.register(with: headless.registrar(forPlugin: "WidgetBridge")) { outcome in
      finish(outcome: outcome)
    }
    engine = headless
    if !headless.run(withEntrypoint: "backgroundFlushMain") {
      quit(outcome: "retry")
    }
  }

  // A log still inside its Undo hold gets one more run, if a whole run fits
  // in the budget after it falls due; anything else left is the helper's to
  // retry.
  private static func finish(outcome: String?) {
    guard !ended else { return }
    stopEngine()
    let due = LogQueue.pending().map { $0.date.addingTimeInterval(queuedLogHold) }.max()
    if outcome == "retry", let due, due > Date(), due.timeIntervalSince(startedAt) < budget - runNeeds {
      DispatchQueue.main.asyncAfter(deadline: .now() + due.timeIntervalSinceNow + 0.5) { run() }
      return
    }
    quit(outcome: outcome ?? "retry")
  }

  private static func stopEngine() {
    engine?.shutDownEngine()
    engine = nil
  }

  private static func quit(outcome: String) {
    guard !ended else { return }
    ended = true
    stopEngine()
    if let defaults = UserDefaults(suiteName: appGroup) {
      defaults.set(outcome, forKey: FlushHandoff.outcome)
      defaults.synchronize()
    }
    NSApp.terminate(nil)
  }
}
