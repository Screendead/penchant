import AppKit
import CoreText
import SwiftUI
import WidgetKit

// Renders the shipping Log widget (LogFace) to PNGs at each family, light and
// dark, plus one medium in its Undo state. Fake habits only.

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
  habit("read", "Read", "page", "pages", 3, .filled, [2, 1, 0, 3, 1, 2, 2]),
  habit("juice", "Juice", "glass", "glasses", 0, .dotted, [0, 1, 0, 0, 1, 0, 1]),
], top: ["coffee", "tea", "water", "walk", "sweets", "stretch", "read", "juice"])
let week = Week(snapshot: snapshot, endingOn: Date())

struct Size { let name: String; let w: CGFloat; let h: CGFloat; let family: WidgetFamily; let count: Int }
let platforms: [(String, [Size], CGFloat)] = [
  ("ios", [Size(name: "small", w: 170, h: 170, family: .systemSmall, count: 1),
           Size(name: "medium", w: 364, h: 170, family: .systemMedium, count: 3),
           Size(name: "large", w: 364, h: 382, family: .systemLarge, count: 8)], 22),
  ("mac", [Size(name: "small", w: 158, h: 158, family: .systemSmall, count: 1),
           Size(name: "medium", w: 338, h: 158, family: .systemMedium, count: 3),
           Size(name: "large", w: 338, h: 354, family: .systemLarge, count: 8)], 20),
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
  let undo = LastLog(id: "x", viceID: "tea", at: Date().timeIntervalSince1970 * 1000)
  for (platform, sizes, corner) in platforms {
    for size in sizes {
      for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        let habits = Array(week.habits.prefix(size.count))
        render(LogFace(family: size.family, habits: habits, undo: nil), size, corner, dark: dark,
          to: "\(platform)-log-\(size.name)-\(mode)")
        if size.family == .systemMedium {
          render(LogFace(family: size.family, habits: habits, undo: undo), size, corner, dark: dark,
            to: "\(platform)-log-medium-undo-\(mode)")
        }
      }
    }
  }
}
