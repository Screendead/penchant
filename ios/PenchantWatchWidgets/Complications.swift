import AppIntents
import SwiftUI
import WidgetKit

// The watch-face complications and Smart Stack widget: one habit's total
// today, from the watch's own store (WatchStore). A tap opens the watch app on
// that habit: Apple's "Adding interactivity to widgets and Live Activities"
// allows buttons in accessory widgets "on iPhone and iPad" only, and a log
// made here could not reach WCSession, which the app holds.

struct WatchHabitEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
  static let defaultQuery = WatchHabitQuery()

  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

  init(_ habit: WatchContext.Habit) {
    id = habit.id
    name = habit.name
  }
}

struct WatchHabitQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [WatchHabitEntity] {
    let habits = WatchStore.context?.habits ?? []
    return identifiers.compactMap { id in habits.first { $0.id == id }.map(WatchHabitEntity.init) }
  }

  func suggestedEntities() async throws -> [WatchHabitEntity] {
    (WatchStore.context?.habits ?? []).map(WatchHabitEntity.init)
  }
}

struct HabitTodayIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Habit today"
  static let description = IntentDescription("Shows one habit's total today.")

  @Parameter(title: "Habit")
  var habit: WatchHabitEntity?

  init() {}

  init(habit: WatchHabitEntity) {
    self.habit = habit
  }
}

struct HabitTodayEntry: TimelineEntry {
  let date: Date
  // Nil while the watch has nothing to show: no context yet, signed out, or
  // the habit is gone.
  let row: WatchBoard.Row?
}

struct HabitTodayProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> HabitTodayEntry { HabitTodayEntry(date: Date(), row: nil) }

  func snapshot(for configuration: HabitTodayIntent, in context: Context) async -> HabitTodayEntry {
    entry(configuration, at: Date())
  }

  // Again at local midnight: yesterday's total is not today's.
  func timeline(for configuration: HabitTodayIntent, in context: Context) async -> Timeline<HabitTodayEntry> {
    let now = Date()
    let midnight = WatchDay.next(after: now)
    return Timeline(entries: [entry(configuration, at: now), entry(configuration, at: midnight)], policy: .after(midnight))
  }

  // The watch face has no screen to pick a habit on, so each habit is offered
  // as its own complication.
  func recommendations() -> [AppIntentRecommendation<HabitTodayIntent>] {
    (WatchStore.context?.habits ?? []).map {
      AppIntentRecommendation(intent: HabitTodayIntent(habit: WatchHabitEntity($0)), description: $0.name)
    }
  }

  // The chosen habit, else the first.
  private func entry(_ configuration: HabitTodayIntent, at date: Date) -> HabitTodayEntry {
    let board = WatchStore.board(at: date)
    return HabitTodayEntry(date: date, row: board.row(configuration.habit?.id) ?? board.rows.first)
  }
}

struct HabitTodayView: View {
  @Environment(\.widgetFamily) private var family
  let entry: HabitTodayEntry

  private var total: String { entry.row.map { watchCount($0.total) } ?? "–" }
  private var name: String { entry.row?.habit.name ?? "Penchant" }
  private var tint: Color { entry.row.map { WatchPalette.ink($0.habit.slot) } ?? WatchPalette.text }

  var body: some View {
    content
      .containerBackground(.clear, for: .widget)
      .widgetURL(entry.row.flatMap { WatchHabitLink.url($0.id) })
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(entry.row.map { "\($0.habit.name), \(total) \($0.unit) today" } ?? "Penchant")
  }

  @ViewBuilder private var content: some View {
    switch family {
    case .accessoryInline:
      Text(entry.row.map { "\($0.habit.name) \(total)" } ?? "Penchant")
    case .accessoryRectangular:
      HStack(spacing: 8) {
        if let row = entry.row {
          WatchMark(habit: row.habit, lineWidth: 2)
            .frame(width: 12, height: 12)
            .widgetAccentable()
        }
        VStack(alignment: .leading, spacing: 0) {
          Text(name)
            .font(.headline)
            .foregroundStyle(tint)
            .widgetAccentable()
            .lineLimit(1)
          Text(entry.row.map { "\(total) \($0.unit) today" } ?? "Open the app on your iPhone")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    case .accessoryCorner:
      Text(total)
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .foregroundStyle(tint)
        .widgetAccentable()
        .minimumScaleFactor(0.6)
        .widgetLabel(name)
    default:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: -2) {
          Text(total)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .widgetAccentable()
            .minimumScaleFactor(0.6)
          // Cut rather than shrunk past legibility: the bezel's label and
          // the habit's colour name it too.
          Text(name)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 4)
      }
      .widgetLabel(name)
    }
  }
}

@main
struct PenchantComplications: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "habit-today", intent: HabitTodayIntent.self, provider: HabitTodayProvider()) {
      HabitTodayView(entry: $0)
    }
    .configurationDisplayName("Habit today")
    .description("One habit's total today. A tap opens Penchant to log it.")
    .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
  }
}
