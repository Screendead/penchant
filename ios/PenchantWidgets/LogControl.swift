#if os(iOS)
  import AppIntents
  import SwiftUI
  import WidgetKit

  @available(iOS 18.0, *)
  struct LogControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Habit"

    @Parameter(title: "Habit")
    var habit: HabitEntity?
  }

  @available(iOS 18.0, *)
  struct LogControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: LogControlIntent) -> HabitEntity? { configuration.habit }

    // Resolved again from the snapshot, so a renamed habit shows its new name.
    func currentValue(configuration: LogControlIntent) async throws -> HabitEntity? {
      guard let id = configuration.habit?.id else { return nil }
      return Snapshot.load()?.habit(id).map(HabitEntity.init) ?? configuration.habit
    }
  }

  // Control Centre, the Lock Screen and the Action button: logs one of the
  // habit chosen when the control was added.
  @available(iOS 18.0, *)
  struct LogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
      AppIntentControlConfiguration(kind: "LogControl", provider: LogControlProvider()) { habit in
        ControlWidgetButton(action: LogOneIntent(habit: habit)) {
          Label(habit.map { "Log \($0.name)" } ?? "Choose a habit", systemImage: "plus.circle")
        }
      }
      .displayName("Log one")
      .description("Logs one of a habit in Penchant.")
      .promptsForUserConfiguration()
    }
  }
#endif
