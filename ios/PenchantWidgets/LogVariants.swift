import AppIntents
import SwiftUI
import WidgetKit

// Round 11 pitch: three faces for the Log widget, drawn in the dial's language
// (the surface disc, the beads, Red Hat type, the data palette). Not in any
// target yet; docs/pitch/round-11/log-widgets/ renders them. The pick replaces
// LogView's grid.

enum LogVariant: String, CaseIterable {
  case rings, hero, glow
}

enum LogSize {
  case small, medium, large

  var count: Int {
    switch self {
    case .small: 1
    case .medium: 3
    case .large: 6
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct LogVariantView: View {
  let variant: LogVariant
  let size: LogSize
  let habits: [HabitWeek]

  var body: some View {
    switch variant {
    case .rings: RingsFace(size: size, habits: habits)
    case .hero: HeroFace(size: size, habits: habits)
    case .glow: GlowFace(size: size, habits: habits)
    }
  }
}

// The tap target every face uses: one of the habit, now.
@available(iOS 17.0, macOS 14.0, *)
struct LogTap<Label: View>: View {
  let habit: HabitWeek
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(intent: LogOneIntent(habit: HabitEntity(habit.habit)), label: label)
      .buttonStyle(.plain)
      .accessibilityLabel("Log 1 \(habit.habit.unitOne) of \(habit.habit.name). \(habit.today) today.")
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

// MARK: - A. Rings: one small dial per habit.

// A disc like the dial's, a ring that fills with today against this week's
// busiest day, the week's seven beads around its rim and the count at its hub.
@available(iOS 17.0, macOS 14.0, *)
struct HabitDial: View {
  let habit: HabitWeek
  var beads = true

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    GeometryReader { g in
      let side = min(g.size.width, g.size.height)
      let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
      let r = side / 2
      let slot = habit.habit.slot
      ZStack {
        Circle().fill(Palette.surface)
          .overlay(Circle().stroke(Palette.line, lineWidth: 1))
          .frame(width: side, height: side)
        Circle().stroke(Palette.fill(slot).opacity(0.18), lineWidth: r * 0.13)
          .frame(width: side * 0.74, height: side * 0.74)
        Circle().trim(from: 0, to: max(0.02, habit.todayShare))
          .stroke(Palette.fill(slot), style: StrokeStyle(lineWidth: r * 0.13, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .frame(width: side * 0.74, height: side * 0.74)
          .shadow(color: colorScheme == .dark ? Palette.fill(slot).opacity(0.45) : .clear, radius: 4)
        if beads {
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
        }
        VStack(spacing: -2) {
          Text("\(habit.today)").font(Typeface.mono(r * 0.42, .medium)).foregroundStyle(Palette.text)
            .contentTransition(.numericText())
          Text("today").font(Typeface.text(max(8, r * 0.13))).foregroundStyle(Palette.muted)
        }
        .position(c)
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

@available(iOS 17.0, macOS 14.0, *)
private struct RingsFace: View {
  let size: LogSize
  let habits: [HabitWeek]

  var body: some View {
    switch size {
    case .small:
      LogTap(habit: habits[0]) {
        VStack(spacing: 6) {
          HabitDial(habit: habits[0])
          label(habits[0], plus: true)
        }
      }
    case .medium:
      HStack(spacing: 10) {
        ForEach(habits.prefix(3)) { habit in
          LogTap(habit: habit) {
            VStack(spacing: 6) {
              HabitDial(habit: habit)
              label(habit, plus: false)
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
    case .large:
      VStack(alignment: .leading, spacing: 10) {
        title
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
          ForEach(habits.prefix(6)) { habit in
            LogTap(habit: habit) {
              VStack(spacing: 5) {
                HabitDial(habit: habit)
                label(habit, plus: false)
              }
            }
          }
        }
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
  }

  private var title: some View {
    Text("Tap to log").font(Typeface.display(15, .bold)).foregroundStyle(Palette.text)
  }

  private func label(_ habit: HabitWeek, plus: Bool) -> some View {
    HStack(spacing: 4) {
      Text(habit.habit.name).font(Typeface.text(12, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
      if plus {
        Text("+1").font(Typeface.mono(11, .bold)).foregroundStyle(Palette.ink(habit.habit.slot))
      }
    }
  }
}

// MARK: - B. Hero: the top habit large, the next two as rows.

@available(iOS 17.0, macOS 14.0, *)
private struct HeroFace: View {
  let size: LogSize
  let habits: [HabitWeek]

  var body: some View {
    switch size {
    case .small:
      LogTap(habit: habits[0]) {
        ZStack(alignment: .bottomTrailing) {
          HabitDial(habit: habits[0])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          PlusBadge(slot: habits[0].habit.slot, side: 30)
        }
        .overlay(alignment: .topLeading) {
          Text(habits[0].habit.name).font(Typeface.display(13, .bold)).foregroundStyle(Palette.text)
        }
      }
    case .medium:
      HStack(spacing: 14) {
        LogTap(habit: habits[0]) {
          ZStack(alignment: .bottomTrailing) {
            HabitDial(habit: habits[0])
            PlusBadge(slot: habits[0].habit.slot, side: 28)
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          Text(habits[0].habit.name).font(Typeface.display(17, .bold)).foregroundStyle(Palette.text)
            .lineLimit(1)
          ForEach(habits.dropFirst().prefix(2)) { RowButton(habit: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    case .large:
      VStack(spacing: 12) {
        HStack(spacing: 14) {
          LogTap(habit: habits[0]) {
            ZStack(alignment: .bottomTrailing) {
              HabitDial(habit: habits[0])
              PlusBadge(slot: habits[0].habit.slot, side: 32)
            }
          }
          .frame(height: 150)
          VStack(alignment: .leading, spacing: 4) {
            Text(habits[0].habit.name).font(Typeface.display(22, .heavy)).foregroundStyle(Palette.text)
            Text("\(habits[0].entryCount) this week").font(Typeface.text(12)).foregroundStyle(Palette.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(spacing: 6) {
          ForEach(habits.dropFirst().prefix(5)) { RowButton(habit: $0) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
private struct RowButton: View {
  let habit: HabitWeek

  var body: some View {
    LogTap(habit: habit) {
      HStack(spacing: 8) {
        Pip(slot: habit.habit.slot, style: habit.habit.style, size: 10)
        Text(habit.habit.name).font(Typeface.text(13, .medium)).foregroundStyle(Palette.text).lineLimit(1)
        Spacer(minLength: 4)
        Text("\(habit.today)").font(Typeface.mono(15)).foregroundStyle(Palette.ink(habit.habit.slot))
        PlusBadge(slot: habit.habit.slot, side: 22)
      }
      .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
      .background(Capsule().fill(Palette.surface))
      .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
struct PlusBadge: View {
  let slot: Int
  let side: CGFloat

  var body: some View {
    Image(systemName: "plus")
      .font(.system(size: side * 0.48, weight: .bold))
      .foregroundStyle(Color.black.opacity(0.78))
      .frame(width: side, height: side)
      .background(Circle().fill(Palette.fill(slot)))
  }
}

// MARK: - C. Glow: a lit tile per habit, its colour rising from the count.

@available(iOS 17.0, macOS 14.0, *)
private struct GlowFace: View {
  let size: LogSize
  let habits: [HabitWeek]

  var body: some View {
    switch size {
    case .small:
      GlowTile(habit: habits[0], big: true)
    case .medium:
      HStack(spacing: 8) {
        ForEach(habits.prefix(3)) { GlowTile(habit: $0, big: false) }
      }
    case .large:
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
        ForEach(habits.prefix(6)) { GlowTile(habit: $0, big: false) }
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }
}

@available(iOS 17.0, macOS 14.0, *)
private struct GlowTile: View {
  let habit: HabitWeek
  let big: Bool

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let slot = habit.habit.slot
    LogTap(habit: habit) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(habit.habit.name).font(Typeface.display(big ? 16 : 13, .bold)).foregroundStyle(Palette.text)
            .lineLimit(1)
          Spacer(minLength: 2)
          PlusBadge(slot: slot, side: big ? 26 : 20)
        }
        Spacer(minLength: 0)
        Text("\(habit.today)").font(Typeface.mono(big ? 44 : 28, .medium)).foregroundStyle(Palette.text)
          .contentTransition(.numericText())
        HStack(spacing: 3) {
          ForEach(0..<Week.length, id: \.self) { day in
            let v = habit.values[day] ?? 0
            let s: CGFloat = v > 0 && habit.peak > 0 ? max(4, (big ? 9 : 7) * CGFloat((v / habit.peak).squareRoot())) : 3
            ZStack {
              if v > 0 {
                Pip(slot: slot, style: habit.habit.style, size: s)
              } else {
                Circle().fill(Palette.line).frame(width: s, height: s)
              }
            }
            .frame(width: big ? 10 : 8, height: big ? 10 : 8)
          }
        }
      }
      .padding(big ? 2 : 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(alignment: .bottomLeading) {
        ZStack(alignment: .bottomLeading) {
          if !big {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface)
          }
          Ellipse()
            .fill(Palette.fill(slot).opacity(colorScheme == .dark ? 0.5 : 0.35))
            .frame(width: big ? 170 : 110, height: big ? 120 : 80)
            .blur(radius: big ? 34 : 22)
            .offset(x: big ? -50 : -34, y: big ? 46 : 34)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        if !big {
          RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1)
        }
      }
    }
  }
}
