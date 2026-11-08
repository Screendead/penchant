import AppKit
import CoreText
import SwiftUI
import WidgetKit

// Renders the Log widget faces in LogVariants.swift, and the shipping Log and
// Last week widgets beside them, to PNGs. Fake habits only.

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
for name in ["RedHatDisplay-Variable", "RedHatText-Variable", "RedHatMono-Variable"] {
  CTFontManagerRegisterFontsForURL(root.appendingPathComponent("assets/fonts/\(name).ttf") as CFURL, .process, nil)
}

let today = Calendar.current.startOfDay(for: Date())
let days = (0..<Week.length).reversed().map { dayKey(Calendar.current.date(byAdding: .day, value: -$0, to: today)!) }
func habit(_ id: String, _ name: String, _ one: String, _ other: String, _ slot: Int, _ style: Snapshot.MarkStyle, _ w: [Double]) -> Snapshot.Habit {
  Snapshot.Habit(id: id, name: name, unitOne: one, unitOther: other, slot: slot, style: style,
    week: w, weekEntries: w.map { Int($0) }, entries30: Int(w.reduce(0, +)) * 4)
}
let snapshot = Snapshot(version: 1, uid: "demo", days: days, habits: [
  habit("coffee", "Coffee", "cup", "cups", 0, .filled, [3, 2, 4, 3, 1, 2, 3]),
  habit("tea", "Tea", "cup", "cups", 1, .filled, [1, 0, 2, 1, 0, 1, 1]),
  habit("water", "Water", "glass", "glasses", 4, .filled, [6, 5, 7, 4, 6, 8, 5]),
  habit("walk", "Walk", "walk", "walks", 3, .ring, [1, 1, 0, 1, 1, 0, 1]),
  habit("sweets", "Sweets", "item", "items", 2, .dotted, [0, 2, 1, 0, 0, 1, 0]),
  habit("stretch", "Stretch", "set", "sets", 1, .ring, [1, 0, 1, 1, 0, 1, 0]),
], top: ["coffee", "tea", "water", "walk", "sweets", "stretch"])
let week = Week(snapshot: snapshot, endingOn: Date())

struct Size { let name: String; let w: CGFloat; let h: CGFloat; let log: LogSize; let family: WidgetFamily }
let platforms: [(String, [Size], CGFloat)] = [
  ("ios", [Size(name: "small", w: 170, h: 170, log: .small, family: .systemSmall),
           Size(name: "medium", w: 364, h: 170, log: .medium, family: .systemMedium),
           Size(name: "large", w: 364, h: 382, log: .large, family: .systemLarge)], 22),
  ("mac", [Size(name: "small", w: 158, h: 158, log: .small, family: .systemSmall),
           Size(name: "medium", w: 338, h: 158, log: .medium, family: .systemMedium),
           Size(name: "large", w: 338, h: 354, log: .large, family: .systemLarge)], 20),
]

@MainActor func render<V: View>(_ view: V, _ size: Size, _ corner: CGFloat, dark: Bool, to name: String) {
  NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)
  let framed = view
    .padding(16)
    .frame(width: size.w, height: size.h)
    .background(Palette.bg)
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .padding(14)
    .background(dark ? Color(white: 0.06) : Color(white: 0.86))
    .environment(\.colorScheme, dark ? .dark : .light)
  let r = ImageRenderer(content: framed)
  r.scale = 2
  guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:]) else { print("fail \(name)"); return }
  try! png.write(to: out.appendingPathComponent(name + ".png"))
}

MainActor.assumeIsolated {
  try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
  for (platform, sizes, corner) in platforms {
    for size in sizes {
      for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        let habits = Array(week.habits.prefix(size.log.count))
        for variant in LogVariant.allCases {
          render(LogVariantView(variant: variant, size: size.log, habits: habits), size, corner, dark: dark,
            to: "\(platform)-\(variant.rawValue)-\(size.name)-\(mode)")
        }
        // The shipping faces. WidgetFamily cannot be set outside WidgetKit, so
        // the small dial is WeekDial itself, as LastWeekView draws it and
        // the medium log row is CurrentLogRow, a copy of LogTile's layout.
        if size.log == .small {
          render(WeekDial(week: week), size, corner, dark: dark,
            to: "\(platform)-current-dial-small-\(mode)")
        } else if size.log == .medium {
          render(HStack(spacing: 8) { ForEach(week.habits.prefix(3)) { CurrentLogRow(habit: $0) } }, size, corner,
            dark: dark, to: "\(platform)-current-log-medium-\(mode)")
        }
      }
    }
  }
}

struct CurrentLogRow: View {
  let habit: HabitWeek
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Pip(slot: habit.habit.slot, style: habit.habit.style, size: 8)
        Text(habit.habit.name).font(Typeface.text(11, .medium)).foregroundStyle(Palette.text).lineLimit(1)
      }
      Text("\(habit.today)").font(Typeface.mono(20)).foregroundStyle(Palette.ink(habit.habit.slot))
      Text("+1").font(Typeface.text(10)).foregroundStyle(Palette.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(8)
    .background { RoundedRectangle(cornerRadius: 12).fill(Palette.surface) }
  }
}
