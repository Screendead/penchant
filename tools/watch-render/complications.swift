import SwiftUI
import WidgetKit

// macOS has no accessory widget families, so watch-render.sh compiles a copy of
// Complications.swift whose view switches on this instead, without its @main.
enum RenderFamily {
  case accessoryCircular, accessoryRectangular, accessoryInline, accessoryCorner
}

// watchOS only; the render shows the face without the bezel's label.
extension View {
  func widgetLabel(_ label: String) -> some View { self }
}

// The corner is left out: its face is mostly the curved label the bezel draws.
@MainActor func complications(_ row: WatchBoard.Row?) -> [(String, CGSize, AnyView)] {
  let entry = HabitTodayEntry(date: Date(), row: row)
  let families: [(String, CGSize, RenderFamily)] = [
    ("circular", CGSize(width: 47, height: 47), .accessoryCircular),
    ("rectangular", CGSize(width: 160, height: 70), .accessoryRectangular),
    ("inline", CGSize(width: 160, height: 20), .accessoryInline),
  ]
  return families.map { ($0.0, $0.1, AnyView(HabitTodayView(family: $0.2, entry: entry))) }
}
