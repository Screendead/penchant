import Cocoa
import FlutterMacOS

// The menu bar helper launches this to write what the widgets queued while
// Penchant is closed. It has no window, Dock icon or menu bar, and nothing can
// activate it. It runs the enclosing app's Dart (macSyncFlushMain in
// lib/main.dart) and leaves the outcome in the App Group for the helper. Its
// first keychain access group is the app's, so Firebase Auth's session and the
// journal key are the app's. Its sandbox container is its own and sign-out in
// Penchant cannot clear it, so the Dart keeps the Firestore cache and write
// journal in memory.
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
    if !headless.run(withEntrypoint: "macSyncFlushMain") {
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
