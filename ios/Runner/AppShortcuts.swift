import AppIntents

// Siri, Shortcuts, Spotlight and the Action button (r10-intents A). The
// intent is ios/PenchantWidgets/LogIntents.swift, compiled into this target
// too, since App Shortcuts are read from the app's bundle.
@available(iOS 17.0, macOS 14.0, *)
struct PenchantShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogOneIntent(),
      phrases: [
        "Log \(\.$habit) in \(.applicationName)",
        "Log one in \(.applicationName)",
      ],
      shortTitle: "Log one",
      systemImageName: "plus.circle")
  }
}
