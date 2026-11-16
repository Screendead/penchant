import SwiftUI

@main
struct PenchantWatchApp: App {
  @StateObject private var journal = WatchJournal()
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      HabitList(journal: journal)
        .onAppear { journal.start() }
        .onOpenURL { url in journal.focus = WatchHabitLink.habitID(url) }
        .onChange(of: phase) { _, phase in
          if phase == .active {
            journal.refresh()
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
          Task { @MainActor in journal.refresh() }
        }
    }
    // A context from the iPhone wakes the app: the session's delegate takes
    // it and reloads the complications.
    .backgroundTask(.watchConnectivity) {
      await journal.start()
      await journal.settle()
    }
  }
}
