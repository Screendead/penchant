import AppIntents
import SwiftUI
import WidgetKit

// r10-widget-top D: the most logged habits of the last 30 days unless the
// widget's settings name others.
@available(iOS 17.0, macOS 14.0, *)
struct LogWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Habits"
  static let description = IntentDescription("Leave empty for your most logged habits of the last 30 days.")

  @Parameter(title: "Habits", size: [.systemSmall: 1, .systemMedium: 3, .systemLarge: 8, .systemExtraLarge: 8])
  var habits: [HabitEntity]?
}

struct LogEntry: TimelineEntry {
  let date: Date
  let snapshot: Snapshot?
  let chosen: [String]
  // The log this entry offers to undo; nil once its window has passed.
  let undo: LastLog?
}

@available(iOS 17.0, macOS 14.0, *)
struct LogProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> LogEntry {
    LogEntry(date: Date(), snapshot: .preview, chosen: [], undo: nil)
  }

  func snapshot(for configuration: LogWidgetIntent, in context: Context) async -> LogEntry {
    let snapshot = Snapshot.load() ?? (context.isPreview ? .preview : nil)
    return LogEntry(date: Date(), snapshot: snapshot, chosen: ids(configuration), undo: nil)
  }

  // Undo shows until its window closes, then a second entry takes it away.
  // Midnight moves today's counts on.
  func timeline(for configuration: LogWidgetIntent, in context: Context) async -> Timeline<LogEntry> {
    let now = Date()
    let snapshot = Snapshot.load()
    let chosen = ids(configuration)
    var entries: [LogEntry] = []
    if let last = LastLog.load(), last.undoUntil > now {
      entries.append(LogEntry(date: now, snapshot: snapshot, chosen: chosen, undo: last))
      entries.append(LogEntry(date: last.undoUntil, snapshot: snapshot, chosen: chosen, undo: nil))
    } else {
      entries.append(LogEntry(date: now, snapshot: snapshot, chosen: chosen, undo: nil))
    }
    let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
    entries.append(LogEntry(date: midnight, snapshot: snapshot, chosen: chosen, undo: nil))
    return Timeline(entries: entries, policy: .never)
  }

  private func ids(_ configuration: LogWidgetIntent) -> [String] {
    (configuration.habits ?? []).map(\.id)
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct LogWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "Log", intent: LogWidgetIntent.self, provider: LogProvider()) { entry in
      LogView(entry: entry)
        .containerBackground(for: .widget) { Palette.bg }
    }
    .configurationDisplayName("Log")
    .description("Log one with a tap: your top 1, 3 or 8 habits.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct LogView: View {
  let entry: LogEntry

  @Environment(\.widgetFamily) private var family

  private var count: Int {
    switch family {
    case .systemSmall: 1
    case .systemMedium: 3
    default: 8
    }
  }

  var body: some View {
    if let snapshot = entry.snapshot, snapshot.uid != nil {
      let habits = snapshot.shown(entry.chosen, count: count)
      let today = Week(snapshot: snapshot, endingOn: entry.date)
      if habits.isEmpty {
        message("Add a habit in Penchant to log it here.")
      } else {
        grid(habits.map { habit in today.habits.first { $0.id == habit.id }! })
      }
    } else {
      message("Open Penchant to log from here.")
    }
  }

  private func message(_ text: String) -> some View {
    Text(text).font(Typeface.text(13)).foregroundStyle(Palette.muted)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func grid(_ habits: [HabitWeek]) -> some View {
    switch family {
    case .systemSmall:
      LogTile(habit: habits[0], undo: undo(for: habits[0]), large: true)
    case .systemMedium:
      HStack(spacing: 8) {
        ForEach(habits) { LogTile(habit: $0, undo: undo(for: $0), large: false) }
      }
    default:
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        ForEach(habits) { LogTile(habit: $0, undo: undo(for: $0), large: false) }
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  private func undo(for habit: HabitWeek) -> LastLog? {
    entry.undo?.viceID == habit.id ? entry.undo : nil
  }
}

// One habit: a tap logs one; for 5 seconds after, the same place offers Undo
// (r10-widget-undo B).
@available(iOS 17.0, macOS 14.0, *)
private struct LogTile: View {
  let habit: HabitWeek
  let undo: LastLog?
  let large: Bool

  private var today: Int { habit.entries.last.flatMap { $0 } ?? 0 }

  var body: some View {
    if let undo {
      Button(intent: UndoLogIntent(activityID: undo.id)) {
        tile {
          Text("Logged").font(Typeface.text(large ? 13 : 11)).foregroundStyle(Palette.muted)
          Text("Undo").font(Typeface.display(large ? 22 : 15, .bold)).foregroundStyle(Palette.ink(habit.habit.slot))
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Undo the log of \(habit.habit.name)")
    } else {
      Button(intent: LogOneIntent(habit: HabitEntity(habit.habit))) {
        tile {
          HStack(spacing: 4) {
            Pip(slot: habit.habit.slot, style: habit.habit.style, size: large ? 10 : 8)
            Text(habit.habit.name).font(Typeface.text(large ? 13 : 11, .medium)).foregroundStyle(Palette.text)
              .lineLimit(1)
          }
          Text("\(today)").font(Typeface.mono(large ? 34 : 20)).foregroundStyle(Palette.ink(habit.habit.slot))
            .invalidatableContent()
            .contentTransition(.numericText())
          Text(large ? "today · tap to log" : "+1").font(Typeface.text(large ? 11 : 10)).foregroundStyle(Palette.muted)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Log 1 \(habit.habit.unitOne) of \(habit.habit.name). \(today) today.")
    }
  }

  private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 2, content: content)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(large ? 0 : 8)
      .background {
        if !large { RoundedRectangle(cornerRadius: 12).fill(Palette.surface) }
      }
  }
}
