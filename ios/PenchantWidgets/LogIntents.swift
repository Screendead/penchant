import AppIntents
import WidgetKit

// Compiled into the app and the widget extension: App Shortcuts must be
// declared in the app, widgets and controls in the extension, and both run
// the same intent.

@available(iOS 17.0, macOS 14.0, *)
struct HabitEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
  static let defaultQuery = HabitQuery()

  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

  init(_ habit: Snapshot.Habit) {
    id = habit.id
    name = habit.name
  }
}

// The habits come from the snapshot the app last wrote, so only the signed-in
// user's unarchived, unlocked habits are offered.
@available(iOS 17.0, macOS 14.0, *)
struct HabitQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [HabitEntity] {
    let habits = Snapshot.load()?.habits ?? []
    return identifiers.compactMap { id in habits.first { $0.id == id }.map(HabitEntity.init) }
  }

  func entities(matching string: String) async throws -> [HabitEntity] {
    (Snapshot.load()?.habits ?? [])
      .filter { $0.name.localizedCaseInsensitiveContains(string) }
      .map(HabitEntity.init)
  }

  func suggestedEntities() async throws -> [HabitEntity] {
    (Snapshot.load()?.shown([], count: .max) ?? []).map(HabitEntity.init)
  }
}

@available(iOS 17.0, macOS 14.0, *)
enum LogError: Error, CustomLocalizedStringResourceConvertible {
  case signedOut
  case unknownHabit
  case notSaved

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .signedOut: "Open Penchant and sign in first."
    case .unknownHabit: "That habit is not in Penchant any more."
    case .notSaved: "Penchant could not save that. Try again in the app."
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct LogOneIntent: AppIntent {
  static let title: LocalizedStringResource = "Log one"
  static let description = IntentDescription("Logs one of a habit in Penchant, now.")

  @Parameter(title: "Habit")
  var habit: HabitEntity?

  init() {}

  init(habit: HabitEntity?) {
    self.habit = habit
  }

  static var parameterSummary: some ParameterSummary {
    Summary("Log one of \(\.$habit)")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let habit else { throw $habit.needsValueError("Which habit?") }
    guard let snapshot = Snapshot.load(), let uid = snapshot.uid else { throw LogError.signedOut }
    guard let found = snapshot.habit(habit.id) else { throw LogError.unknownHabit }
    guard let log = LogQueue.log(uid: uid, viceID: found.id) else { throw LogError.notSaved }
    LastLog.save(LastLog(id: log.id, viceID: found.id, at: log.createdAt))
    reloadEverything()
    return .result(dialog: "Logged 1 \(found.unitOne) of \(found.name).")
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct UndoLogIntent: AppIntent {
  static let title: LocalizedStringResource = "Undo the last log"
  // Only a widget's Undo button runs it, with the id of the log it shows.
  static let isDiscoverable = false

  @Parameter(title: "Entry")
  var activityID: String

  init() {}

  init(activityID: String) {
    self.activityID = activityID
  }

  func perform() async throws -> some IntentResult {
    guard let last = LastLog.load(), last.id == activityID,
      let uid = Snapshot.load()?.uid
    else { return .result() }
    if LogQueue.undo(last, uid: uid) {
      LastLog.save(nil)
    }
    reloadEverything()
    return .result()
  }
}

@available(iOS 17.0, macOS 14.0, *)
func reloadEverything() {
  WidgetCenter.shared.reloadAllTimelines()
  #if os(iOS)
    if #available(iOS 18.0, *) {
      ControlCenter.shared.reloadAllControls()
    }
  #endif
}
