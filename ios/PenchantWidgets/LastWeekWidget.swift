import SwiftUI
import WidgetKit

struct LastWeekEntry: TimelineEntry {
  let date: Date
  let snapshot: Snapshot?

  var week: Week? { snapshot.map { Week(snapshot: $0, endingOn: date) } }
}

// The app reloads the timelines whenever it writes a snapshot. Between those,
// one entry per midnight moves the week on, so a day the app has not seen
// shows as no data rather than last week's numbers under the wrong day.
struct LastWeekProvider: TimelineProvider {
  func placeholder(in context: Context) -> LastWeekEntry {
    LastWeekEntry(date: Date(), snapshot: .preview)
  }

  func getSnapshot(in context: Context, completion: @escaping (LastWeekEntry) -> Void) {
    completion(LastWeekEntry(date: Date(), snapshot: Snapshot.load() ?? (context.isPreview ? .preview : nil)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LastWeekEntry>) -> Void) {
    let now = Date()
    let snapshot = Snapshot.load()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let midnights = (1...Week.length).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    let entries = [LastWeekEntry(date: now, snapshot: snapshot)]
      + midnights.map { LastWeekEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

struct LastWeekWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LastWeek", provider: LastWeekProvider()) { entry in
      LastWeekView(entry: entry)
        .containerBackground(for: .widget) { Palette.bg }
    }
    .configurationDisplayName("Last week")
    .description("Every habit over the last 7 days.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
      .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ])
  }
}

struct LastWeekView: View {
  let entry: LastWeekEntry

  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let week = entry.week, let snapshot = entry.snapshot {
      content(week, snapshot)
    } else {
      empty
    }
  }

  @ViewBuilder
  private func content(_ week: Week, _ snapshot: Snapshot) -> some View {
    switch family {
    case .accessoryCircular:
      WeekDial(week: week, showsLabels: false)
    case .accessoryRectangular:
      RectangularView(week: week, top: snapshot.top)
    case .accessoryInline:
      InlineView(week: week, top: snapshot.top)
    case .systemSmall:
      WeekDial(week: week)
    case .systemMedium:
      HStack(spacing: 14) {
        WeekDial(week: week).aspectRatio(1, contentMode: .fit)
        HabitList(week: week, rows: 4, strips: false)
      }
    case .systemLarge:
      VStack(alignment: .leading, spacing: 10) {
        Header(week: week)
        WeekDial(week: week).frame(maxHeight: .infinity)
        HabitList(week: week, rows: 5, strips: true)
      }
    default:
      HStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 10) {
          Header(week: week)
          WeekDial(week: week)
        }
        .aspectRatio(0.9, contentMode: .fit)
        HabitList(week: week, rows: 10, strips: true)
      }
    }
  }

  @ViewBuilder
  private var empty: some View {
    switch family {
    case .accessoryInline:
      Text("Open Penchant")
    case .accessoryCircular:
      Image(systemName: "circle.dashed").font(.title)
    default:
      VStack(alignment: .leading, spacing: 4) {
        Text("Last week").font(Typeface.display(17, .bold)).foregroundStyle(Palette.text)
        Text("Open Penchant to show your habits here.")
          .font(Typeface.text(13)).foregroundStyle(Palette.muted)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

private struct Header: View {
  let week: Week

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Last 7 days").font(Typeface.display(17, .bold)).foregroundStyle(Palette.text)
      Spacer()
      Text(range).font(Typeface.mono(11)).foregroundStyle(Palette.muted)
    }
  }

  private var range: String {
    guard let first = week.days.first, let last = week.days.last else { return "" }
    let formatter = DateIntervalFormatter()
    formatter.dateTemplate = "dMMM"
    return formatter.string(from: first, to: last)
  }
}

// Habits in the app's order (Today's), with "+N more" past [rows].
private struct HabitList: View {
  let week: Week
  let rows: Int
  let strips: Bool

  var body: some View {
    let shown = week.habits.prefix(rows)
    VStack(alignment: .leading, spacing: strips ? 6 : 5) {
      if week.habits.isEmpty {
        Text("No habits yet").font(Typeface.text(13)).foregroundStyle(Palette.muted)
      }
      ForEach(Array(shown)) { habit in
        HabitRow(habit: habit, strip: strips)
      }
      if week.habits.count > rows {
        Text("+\(week.habits.count - rows) more").font(Typeface.text(11)).foregroundStyle(Palette.muted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HabitRow: View {
  let habit: HabitWeek
  let strip: Bool

  var body: some View {
    let zero = habit.total == 0
    HStack(spacing: 6) {
      Pip(slot: habit.habit.slot, style: habit.habit.style, size: 8).opacity(zero ? 0.4 : 1)
      Text(habit.habit.name)
        .font(Typeface.text(13, .medium))
        .foregroundStyle(zero ? Palette.muted : Palette.text)
        .lineLimit(1)
      Spacer(minLength: 4)
      if strip {
        DayStrip(habit: habit)
      }
      Text(formatCount(habit.total))
        .font(Typeface.mono(13))
        .foregroundStyle(zero ? Palette.muted : Palette.ink(habit.habit.slot))
      Text(habit.total == 1 ? habit.habit.unitOne : habit.habit.unitOther)
        .font(Typeface.text(11))
        .foregroundStyle(Palette.muted)
        .lineLimit(1)
        .fixedSize()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(habit.habit.name), \(habit.totalLabel)")
  }
}

// One bead per day, oldest first, sized as on the dial.
private struct DayStrip: View {
  let habit: HabitWeek

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<Week.length, id: \.self) { day in
        let value = habit.values[day] ?? 0
        let size: CGFloat = value > 0 && habit.peak > 0 ? max(4, 10 * CGFloat((value / habit.peak).squareRoot())) : 3
        ZStack {
          if value > 0 {
            Pip(slot: habit.habit.slot, style: habit.habit.style, size: size)
          } else {
            Circle().fill(Palette.line).frame(width: size, height: size)
          }
        }
        .frame(width: 10, height: 10)
      }
    }
  }
}

struct Pip: View {
  let slot: Int
  let style: Snapshot.MarkStyle
  let size: CGFloat

  var body: some View {
    switch style {
    case .filled:
      Circle().fill(Palette.fill(slot)).frame(width: size, height: size)
    case .ring:
      Circle().strokeBorder(Palette.ink(slot), lineWidth: max(1, size * 0.25)).frame(width: size, height: size)
    case .dotted:
      Circle()
        .strokeBorder(
          Palette.ink(slot), style: StrokeStyle(lineWidth: max(1, size * 0.25), dash: [max(1, size * 0.2)]))
        .frame(width: size, height: size)
    }
  }
}

// The top habits (r10-widget-top) that have anything this week, else the top.
private func lockScreenHabits(_ week: Week, _ top: [String], count: Int) -> [HabitWeek] {
  let byID = Dictionary(uniqueKeysWithValues: week.habits.map { ($0.id, $0) })
  let ranked = top.compactMap { byID[$0] }
  let active = ranked.filter { $0.total > 0 }
  return Array((active.isEmpty ? ranked : active).prefix(count))
}

private struct RectangularView: View {
  let week: Week
  let top: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Last 7 days").font(.headline).widgetAccentable()
      ForEach(lockScreenHabits(week, top, count: 3)) { habit in
        HStack(spacing: 4) {
          Text(habit.habit.name).lineLimit(1)
          Spacer(minLength: 2)
          Text(formatCount(habit.total)).monospacedDigit()
        }
        .font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary(week))
  }
}

private struct InlineView: View {
  let week: Week
  let top: [String]

  var body: some View {
    let habits = lockScreenHabits(week, top, count: 3)
    ViewThatFits {
      ForEach((1...max(1, habits.count)).reversed(), id: \.self) { n in
        Text(habits.prefix(n).map { "\($0.habit.name) \(formatCount($0.total))" }.joined(separator: " · "))
      }
    }
  }
}

extension Snapshot {
  // Made-up habits for the gallery and placeholders.
  static var preview: Snapshot {
    let today = Calendar.current.startOfDay(for: Date())
    return Snapshot(
    version: supportedVersion,
    days: (0..<Week.length).reversed().map {
      dayKey(Calendar.current.date(byAdding: .day, value: -$0, to: today)!)
    },
    habits: [
      .init(
        id: "coffee", name: "Coffee", unitOne: "drink", unitOther: "drinks", slot: 0, style: .filled,
        week: [3, 2, 4, 3, 1, 2, 3], weekEntries: [3, 2, 4, 3, 1, 2, 3], entries30: 60),
      .init(
        id: "tea", name: "Tea", unitOne: "drink", unitOther: "drinks", slot: 1, style: .filled,
        week: [1, 0, 2, 1, 0, 1, 2], weekEntries: [1, 0, 2, 1, 0, 1, 2], entries30: 20),
      .init(
        id: "takeaway", name: "Takeaway", unitOne: "item", unitOther: "items", slot: 2, style: .filled,
        week: [0, 1, 0, 0, 1, 0, 0], weekEntries: [0, 1, 0, 0, 1, 0, 0], entries30: 6),
    ],
    top: ["coffee", "tea", "takeaway"])
  }
}
