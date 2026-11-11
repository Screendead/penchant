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
  var waiting = false
  // The log this entry offers to say what was going on about, for longer.
  var ask: LastLog?
}

@available(iOS 17.0, macOS 14.0, *)
struct LogProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> LogEntry {
    LogEntry(date: Date(), snapshot: .preview, chosen: [], undo: nil)
  }

  func snapshot(for configuration: LogWidgetIntent, in context: Context) async -> LogEntry {
    let now = Date()
    let snapshot = Snapshot.load() ?? (context.isPreview ? .preview : nil)
    return LogEntry(
      date: now, snapshot: snapshot, chosen: ids(configuration), undo: nil,
      waiting: !context.isPreview && QueuedWait.current(now: now).waiting(at: now))
  }

  // Undo shows until its window closes, then a second entry takes it away;
  // "What was going on?" stays until its own window closes. Midnight moves
  // today's counts on. On the Mac, logs no helper will write say so once past
  // their hold.
  func timeline(for configuration: LogWidgetIntent, in context: Context) async -> Timeline<LogEntry> {
    let now = Date()
    let snapshot = Snapshot.load()
    let chosen = ids(configuration)
    let wait = QueuedWait.current(now: now)
    let last = LastLog.current(at: now)
    let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
    let ends = last.map { [$0.undoUntil, $0.askUntil].filter { $0 > now && $0 < midnight } } ?? []
    let dates = [now] + ends + [midnight]
    let entries = wait.dates(dates, now: now).map { date in
      LogEntry(
        date: date, snapshot: snapshot, chosen: chosen, undo: last.flatMap { date < $0.undoUntil ? $0 : nil },
        waiting: wait.waiting(at: date), ask: last.flatMap { $0.askable(at: date) ? $0 : nil })
    }
    let policy: TimelineReloadPolicy = wait.recheck.map { .after($0) } ?? .atEnd
    return Timeline(entries: entries, policy: policy)
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
        LogFace(
          family: family, habits: habits.map { habit in today.habits.first { $0.id == habit.id }! },
          undo: entry.undo, waiting: entry.waiting,
          ask: entry.ask.flatMap { log in habits.contains { $0.id == log.viceID } ? log : nil })
      }
    } else {
      message("Open Penchant to log from here.")
    }
  }

  private func message(_ text: String) -> some View {
    Text(text).font(Typeface.text(13)).foregroundStyle(Palette.muted)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

// Jack 2026-11-08: Hero with Glow. The first habit is a dial with a + badge;
// the rest are pills with their count and a + button. Each sits on a soft glow
// of its own colour.
@available(iOS 17.0, macOS 14.0, *)
struct LogFace: View {
  let family: WidgetFamily
  let habits: [HabitWeek]
  let undo: LastLog?
  var waiting = false
  // Only a log of a habit this widget shows.
  var ask: LastLog?

  var body: some View {
    let hero = habits[0]
    switch family {
    case .systemSmall:
      VStack(alignment: .leading, spacing: 4) {
        Text(hero.habit.name).font(Typeface.display(13, .bold)).foregroundStyle(Palette.text).lineLimit(1)
        HeroDial(habit: hero, undo: undo(for: hero), badge: 28)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let ask { AskLink(log: ask) }
        if waiting { WaitingNotice() }
      }
    case .systemMedium:
      HStack(spacing: 14) {
        HeroDial(habit: hero, undo: undo(for: hero), badge: 28)
        VStack(alignment: .leading, spacing: 8) {
          Text(hero.habit.name).font(Typeface.display(17, .bold)).foregroundStyle(Palette.text).lineLimit(1)
          ForEach(habits.dropFirst().prefix(2)) { HabitPill(habit: $0, undo: undo(for: $0)) }
          if let ask { AskLink(log: ask) }
          if waiting { WaitingNotice() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    default:
      VStack(spacing: 12) {
        HStack(spacing: 14) {
          HeroDial(habit: hero, undo: undo(for: hero), badge: 32)
            .frame(height: 140)
          VStack(alignment: .leading, spacing: 4) {
            Text(hero.habit.name).font(Typeface.display(22, .heavy)).foregroundStyle(Palette.text).lineLimit(1)
            Text("\(hero.today) today · \(hero.entryCount) this week").font(Typeface.text(12))
              .foregroundStyle(Palette.muted).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
          ForEach(habits.dropFirst()) { HabitPill(habit: $0, undo: undo(for: $0)) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        if let ask { AskLink(log: ask).frame(maxWidth: .infinity, alignment: .leading) }
        if waiting { WaitingNotice().frame(maxWidth: .infinity, alignment: .leading) }
      }
    }
  }

  private func undo(for habit: HabitWeek) -> LastLog? {
    undo?.viceID == habit.id ? undo : nil
  }
}

extension HabitWeek {
  var today: Int { entries.last.flatMap { $0 } ?? 0 }
  // Today against the habit's busiest day this week, so the ring fills as a
  // day catches up with that week's high.
  var todayShare: Double {
    let peak = entries.compactMap { $0 }.max() ?? 0
    return peak > 0 ? min(1, Double(today) / Double(peak)) : 0
  }
}

// A tap logs one; for 5 seconds after, the same place offers Undo
// (r10-widget-undo B).
@available(iOS 17.0, macOS 14.0, *)
private struct LogButton<Label: View>: View {
  let habit: HabitWeek
  let undo: LastLog?
  @ViewBuilder let label: () -> Label

  var body: some View {
    if let undo {
      Button(intent: UndoLogIntent(activityID: undo.id), label: label)
        .buttonStyle(.plain)
        .accessibilityLabel("Undo the log of \(habit.habit.name)")
    } else {
      Button(intent: LogOneIntent(habit: HabitEntity(habit.habit)), label: label)
        .buttonStyle(.plain)
        .accessibilityLabel("Log 1 \(habit.habit.unitOne) of \(habit.habit.name). \(habit.today) today.")
    }
  }
}

// Opens Penchant at the entry to say what was going on. A widget cannot show
// the picker, and a button's intent should do more than open the app, so it
// is a Link ("Linking to specific app scenes from your widget or Live
// Activity", developer.apple.com), beside the log buttons, not inside one.
@available(iOS 17.0, macOS 14.0, *)
private struct AskLink: View {
  let log: LastLog

  var body: some View {
    if let url = EntryLink.url(log) {
      Link(destination: url) {
        HStack(spacing: 4) {
          Image(systemName: "text.bubble").font(.system(size: 10, weight: .semibold))
          Text("What was going on?").font(Typeface.text(12, .semibold)).lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Palette.text)
      }
      .accessibilityLabel("Say what was going on, in Penchant")
    }
  }
}

// The habit's colour, blurred, behind an element. Fainter on the light ground.
@available(iOS 17.0, macOS 14.0, *)
private struct Glow: View {
  let slot: Int
  let strength: Double

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Ellipse()
      .fill(Palette.fill(slot).opacity(strength * (colorScheme == .dark ? 1 : 0.6)))
  }
}

// A disc like the dial's: a ring that fills with today against this week's
// busiest day, the week's seven beads around its rim and the count at its hub.
@available(iOS 17.0, macOS 14.0, *)
private struct HeroDial: View {
  let habit: HabitWeek
  let undo: LastLog?
  let badge: CGFloat

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    LogButton(habit: habit, undo: undo) {
      ZStack(alignment: .bottomTrailing) {
        GeometryReader { g in
          let side = min(g.size.width, g.size.height)
          let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
          let r = side / 2
          let slot = habit.habit.slot
          ZStack {
            Glow(slot: slot, strength: 0.42)
              .frame(width: side * 1.05, height: side * 1.05)
              .blur(radius: side * 0.16)
              .position(c)
            Circle().fill(Palette.surface)
              .overlay(Circle().stroke(Palette.line, lineWidth: 1))
              .frame(width: side, height: side)
              .position(c)
            Circle().stroke(Palette.fill(slot).opacity(0.18), lineWidth: r * 0.13)
              .frame(width: side * 0.74, height: side * 0.74)
              .position(c)
            Circle().trim(from: 0, to: max(0.02, habit.todayShare))
              .stroke(Palette.fill(slot), style: StrokeStyle(lineWidth: r * 0.13, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .frame(width: side * 0.74, height: side * 0.74)
              .shadow(color: Palette.fill(slot).opacity(colorScheme == .dark ? 0.5 : 0.25), radius: 4)
              .position(c)
            ForEach(0..<Week.length, id: \.self) { day in
              let v = habit.values[day] ?? 0
              let s = v > 0 && habit.peak > 0 ? max(0.35, (v / habit.peak).squareRoot()) : 0
              let angle = -Double.pi / 2 + 2 * Double.pi * (Double(day) + 0.5) / Double(Week.length)
              Group {
                if s > 0 {
                  Pip(slot: slot, style: habit.habit.style, size: r * 0.12 * s + 2)
                } else {
                  Circle().fill(Palette.line).frame(width: 2.5, height: 2.5)
                }
              }
              .position(x: c.x + r * 0.9 * cos(angle), y: c.y + r * 0.9 * sin(angle))
            }
            VStack(spacing: -2) {
              if undo != nil {
                Text("Undo").font(Typeface.display(r * 0.3, .bold)).foregroundStyle(Palette.ink(slot))
                Text("logged").font(Typeface.text(max(8, r * 0.13))).foregroundStyle(Palette.muted)
              } else {
                Text("\(habit.today)").font(Typeface.mono(r * 0.42, .medium)).foregroundStyle(Palette.text)
                  .invalidatableContent()
                  .contentTransition(.numericText())
                Text("today").font(Typeface.text(max(8, r * 0.13))).foregroundStyle(Palette.muted)
              }
            }
            .position(c)
          }
        }
        .aspectRatio(1, contentMode: .fit)
        PlusBadge(slot: habit.habit.slot, side: badge, undo: undo != nil)
      }
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
private struct HabitPill: View {
  let habit: HabitWeek
  let undo: LastLog?

  var body: some View {
    let slot = habit.habit.slot
    LogButton(habit: habit, undo: undo) {
      HStack(spacing: 8) {
        Pip(slot: slot, style: habit.habit.style, size: 10)
        Text(habit.habit.name).font(Typeface.text(13, .medium)).foregroundStyle(Palette.text).lineLimit(1)
        Spacer(minLength: 4)
        if undo == nil {
          Text("\(habit.today)").font(Typeface.mono(15)).foregroundStyle(Palette.ink(slot))
            .invalidatableContent()
            .contentTransition(.numericText())
        } else {
          Text("Undo").font(Typeface.text(13, .semibold)).foregroundStyle(Palette.ink(slot))
        }
        PlusBadge(slot: slot, side: 22, undo: undo != nil)
      }
      .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
      .background {
        Capsule().fill(Palette.surface)
          .overlay(alignment: .trailing) {
            Glow(slot: slot, strength: 0.38)
              .frame(width: 70, height: 44)
              .blur(radius: 14)
              .offset(x: 16)
          }
          .compositingGroup()
          .clipShape(Capsule())
      }
      .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
private struct PlusBadge: View {
  let slot: Int
  let side: CGFloat
  var undo = false

  var body: some View {
    Image(systemName: undo ? "arrow.uturn.backward" : "plus")
      .font(.system(size: side * (undo ? 0.42 : 0.48), weight: .bold))
      .foregroundStyle(Color.black.opacity(0.78))
      .frame(width: side, height: side)
      .background(Circle().fill(Palette.fill(slot)))
  }
}
