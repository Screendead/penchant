import SwiftUI
import WidgetKit

struct StubEntry: TimelineEntry { let date: Date }

struct StubProvider: TimelineProvider {
  func placeholder(in context: Context) -> StubEntry { StubEntry(date: .now) }
  func getSnapshot(in context: Context, completion: @escaping (StubEntry) -> Void) { completion(StubEntry(date: .now)) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<StubEntry>) -> Void) {
    completion(Timeline(entries: [StubEntry(date: .now)], policy: .never))
  }
}

@main
struct PenchantComplications: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "stub", provider: StubProvider()) { _ in
      Text("1").containerBackground(.clear, for: .widget)
    }
    .supportedFamilies([.accessoryCircular])
  }
}
