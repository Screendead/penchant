import SwiftUI

// The dark half of lib/design/tokens.json (Day Dial): a watch has no light
// appearance. A token change there is a change here. The page itself is
// black, as the display's surround is; rows sit on the tokens' surfaces.
enum WatchPalette {
  static let surface = rgb(0x1F1D1B)
  static let surface2 = rgb(0x2A2825)
  static let text = rgb(0xF3F0EA)
  static let muted = rgb(0xACA79D)
  static let onAccent = rgb(0x1D1C1A)
  static let wedgeInk = rgb(0x120F0C)

  private static let data = [rgb(0xFFB347), rgb(0xFF7A59), rgb(0xE95963), rgb(0xA973E9), rgb(0x4D96FF)]
  private static let ink = [rgb(0xFFB347), rgb(0xFF7A59), rgb(0xF0737C), rgb(0xB48AF0), rgb(0x4D96FF)]

  static func fill(_ slot: Int) -> Color { data[((slot % 5) + 5) % 5] }
  static func ink(_ slot: Int) -> Color { ink[((slot % 5) + 5) % 5] }

  private static func rgb(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}

// The Red Hat variable fonts, bundled with the watch app (UIAppFonts); sizes
// follow the wearer's text size.
enum WatchType {
  static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
    .custom("Red Hat Display", size: size, relativeTo: .headline).weight(weight)
  }
  static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Red Hat Text", size: size, relativeTo: .body).weight(weight)
  }
  static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .custom("Red Hat Mono", size: size, relativeTo: .title3).weight(weight).monospacedDigit()
  }
}

// A habit's mark as the app draws it (habitMarks): filled for the first five
// habits, a ring for the next five, then a dotted ring.
struct WatchMark: View {
  let habit: WatchContext.Habit
  var lineWidth: CGFloat = 2.5

  var body: some View {
    switch habit.style {
    case "ring":
      Circle().strokeBorder(WatchPalette.fill(habit.slot), lineWidth: lineWidth)
    case "dotted":
      Circle().strokeBorder(
        WatchPalette.fill(habit.slot), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.1, 5]))
    default:
      Circle().fill(WatchPalette.fill(habit.slot))
    }
  }
}
