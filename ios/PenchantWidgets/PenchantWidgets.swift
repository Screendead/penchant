import SwiftUI
import WidgetKit

let appGroup = "group.com.screendead.penchant"
let spikeKey = "spike.lastLaunch"

struct SpikeEntry: TimelineEntry {
  let date: Date
  let text: String
}

struct SpikeProvider: TimelineProvider {
  func placeholder(in context: Context) -> SpikeEntry {
    SpikeEntry(date: Date(), text: "…")
  }

  func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .never))
  }

  private func entry() -> SpikeEntry {
    let defaults = UserDefaults(suiteName: appGroup)
    let text = defaults?.string(forKey: spikeKey) ?? (defaults == nil ? "no group" : "nothing written")
    return SpikeEntry(date: Date(), text: text)
  }
}

struct SpikeWidgetView: View {
  let entry: SpikeEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Penchant").font(.caption).foregroundStyle(.secondary)
      Text(entry.text).font(.headline).minimumScaleFactor(0.5)
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

struct SpikeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PenchantSpike", provider: SpikeProvider()) { entry in
      SpikeWidgetView(entry: entry)
    }
    .configurationDisplayName("Penchant spike")
    .description("Shows what the app last wrote to the shared App Group.")
    .supportedFamilies([.systemSmall])
  }
}

@main
struct PenchantWidgetsBundle: WidgetBundle {
  var body: some Widget {
    SpikeWidget()
  }
}
