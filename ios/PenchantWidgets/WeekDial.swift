import SwiftUI
import WidgetKit

// The Day Dial's face turned to a week: seven sectors, oldest at the top and
// running clockwise to today, one track per habit from the hub outward. A
// bead's area follows the day's amount against that habit's busiest day.
struct WeekDial: View {
  let week: Week
  var showsLabels = true
  var showsHub = true

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    GeometryReader { geometry in
      let side = min(geometry.size.width, geometry.size.height)
      let radius = side / 2 * (showsLabels ? 0.82 : 0.98)
      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
      ZStack {
        Canvas { context, _ in
          draw(in: &context, center: center, radius: radius)
        }
        if showsLabels {
          ForEach(0..<Week.length, id: \.self) { day in
            Text(letter(day))
              .font(Typeface.display(max(8, side * 0.07), .bold))
              .foregroundStyle(day == Week.length - 1 ? Palette.text : Palette.muted)
              .opacity(week.covered[day] ? 1 : 0.4)
              .position(point(center, radius + side * 0.075, angle: middle(of: day)))
          }
        }
        if showsHub {
          VStack(spacing: 0) {
            Text("\(week.entryCount)")
              .font(Typeface.mono(radius * 0.26, .medium))
              .foregroundStyle(vibrant ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.text))
            Text(week.entryCount == 1 ? "entry" : "entries")
              .font(Typeface.text(max(7, radius * 0.11)))
              .foregroundStyle(vibrant ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.muted))
          }
          .minimumScaleFactor(0.5)
          .frame(width: radius * hubShare * 1.7)
          .position(center)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary(week))
  }

  private var hubShare: CGFloat { showsHub ? 0.36 : 0.16 }
  private var vibrant: Bool { renderingMode != .fullColor }

  private func draw(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
    let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    if vibrant {
      context.fill(disc, with: .color(.primary.opacity(0.12)))
    } else {
      context.fill(disc, with: .color(Palette.surface))
      context.stroke(disc, with: .color(Palette.line), lineWidth: 1)
    }

    let hub = radius * hubShare
    for day in 0..<Week.length {
      var spoke = Path()
      let angle = start(of: day)
      spoke.move(to: point(center, hub, angle: angle))
      spoke.addLine(to: point(center, radius, angle: angle))
      context.stroke(spoke, with: .color(vibrant ? .primary.opacity(0.5) : Palette.spoke), lineWidth: 0.75)
    }

    let habits = week.habits
    guard !habits.isEmpty else { return }
    let inner = hub + radius * 0.06
    let outer = radius * 0.94
    let track = (outer - inner) / CGFloat(habits.count)
    let sectorArc = 2 * Double.pi / Double(Week.length)
    for (index, habit) in habits.enumerated() {
      let r = inner + track * (CGFloat(index) + 0.5)
      let biggest = min(track * 0.5, r * CGFloat(sin(sectorArc / 2)) * 0.8)
      let peak = habit.peak
      for day in 0..<Week.length {
        guard let value = habit.values[day], value > 0, peak > 0 else { continue }
        let size = max(biggest * 0.4, biggest * CGFloat((value / peak).squareRoot()))
        drawBead(
          in: &context, at: point(center, r, angle: middle(of: day)), radius: size,
          slot: habit.habit.slot, style: habit.habit.style)
      }
    }
  }

  private func drawBead(
    in context: inout GraphicsContext, at p: CGPoint, radius: CGFloat, slot: Int, style: Snapshot.MarkStyle
  ) {
    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
    let circle = Path(ellipseIn: rect)
    let fill = vibrant ? Color.primary : Palette.fill(slot)
    let ink = vibrant ? Color.primary : Palette.ink(slot)
    switch style {
    case .filled:
      if colorScheme == .dark && !vibrant {
        var glow = context
        glow.addFilter(.blur(radius: 3))
        glow.fill(circle, with: .color(fill.opacity(0.25)))
      }
      context.fill(circle, with: .color(fill))
      if colorScheme == .light && !vibrant {
        let rim = min(1.25, radius * 0.3)
        context.stroke(
          Path(ellipseIn: rect.insetBy(dx: rim / 2, dy: rim / 2)), with: .color(ink.opacity(0.9)), lineWidth: rim)
      }
    case .ring:
      let width = max(1, radius * 0.4)
      context.stroke(
        Path(ellipseIn: rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(ink), lineWidth: width)
    case .dotted:
      let width = max(1, radius * 0.4)
      let circumference = Double.pi * Double(radius * 2 - width)
      let dash = CGFloat(circumference / 12)
      context.stroke(
        Path(ellipseIn: rect.insetBy(dx: width / 2, dy: width / 2)), with: .color(ink),
        style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [dash * 0.45, dash * 0.55]))
    }
  }

  private func start(of day: Int) -> Double {
    -Double.pi / 2 + 2 * Double.pi * Double(day) / Double(Week.length)
  }

  private func middle(of day: Int) -> Double {
    start(of: day) + Double.pi / Double(Week.length)
  }

  private func point(_ center: CGPoint, _ radius: CGFloat, angle: Double) -> CGPoint {
    CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
  }

  private func letter(_ day: Int) -> String {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEEE")
    return formatter.string(from: week.days[day])
  }
}

func summary(_ week: Week) -> String {
  let habits = week.habits.map { "\($0.habit.name) \($0.totalLabel)" }
  let body = habits.isEmpty ? "No habits." : habits.joined(separator: ", ") + "."
  return "Last 7 days. \(body)"
}
