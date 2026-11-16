import AppKit
import CoreText
import SwiftUI

// Renders the watch app's screens and complications on this Mac, from canned
// states, as PNGs at Apple Watch point sizes (tools/watch-render.sh). A Mac
// render is not a watch: no status bar, title chrome or rounded display, and
// macOS font metrics.

// What HabitList reads of the real WatchJournal (WatchSession.swift, which
// needs WatchConnectivity).
@MainActor
final class WatchJournal: ObservableObject {
  @Published var board: WatchBoard
  @Published var last: WatchLog?
  @Published var focus: String?

  init(board: WatchBoard, last: WatchLog? = nil, focus: String? = nil) {
    self.board = board
    self.last = last
    self.focus = focus
  }

  func log(_ habit: WatchContext.Habit) {}
  func undo() {}
  func refresh() {}
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let fonts = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "assets/fonts", isDirectory: true)
for name in ["RedHatDisplay-Variable.ttf", "RedHatMono-Variable.ttf", "RedHatText-Variable.ttf"] {
  CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}

let now = Date()
let today = WatchDay.key(now)
let uid = "render"

func habit(_ id: String, _ name: String, _ one: String, _ other: String, _ n: Int, _ total: Double) -> WatchContext.Habit
{
  let styles = ["filled", "ring", "dotted"]
  return WatchContext.Habit(
    id: id, name: name, unitOne: one, unitOther: other, slot: n % 5, style: styles[(n / 5) % 3], today: total)
}

let eight = [
  habit("coffee", "Coffee", "cup", "cups", 0, 3),
  habit("wine", "Wine", "glass", "glasses", 1, 0),
  habit("cigarettes", "Cigarettes", "cigarette", "cigarettes", 2, 12),
  habit("snacks", "Late-night snacking on the sofa", "snack", "snacks", 3, 1),
  habit("beer", "Beer", "pint", "pints", 4, 2.5),
  habit("cola", "Cola", "can", "cans", 5, 0),
  habit("scroll", "Doomscrolling", "session", "sessions", 6, 4),
  habit("vape", "Vape", "puff", "puffs", 7, 140),
]
let three = Array(eight.prefix(3))

func context(_ habits: [WatchContext.Habit], day: String = today) -> WatchContext {
  WatchContext(uid: uid, day: day, habits: habits, received: [])
}

func board(_ context: WatchContext?, _ outbox: [WatchLog] = []) -> WatchBoard {
  WatchBoard(context: context, outbox: outbox, now: now)
}

let justLogged = WatchLog(uid: uid, viceID: "coffee", at: now.addingTimeInterval(-2))
let waiting = [
  WatchLog(uid: uid, viceID: "coffee", at: now.addingTimeInterval(-90)),
  WatchLog(uid: uid, viceID: "cigarettes", at: now.addingTimeInterval(-60)),
]
let yesterday = WatchDay.key(now.addingTimeInterval(-86400))
let staleLog = WatchLog(uid: uid, viceID: "wine", at: now.addingTimeInterval(-5))

@MainActor func screens() -> [(String, WatchJournal)] { [
  ("today-3", WatchJournal(board: board(context(three)))),
  ("today-8", WatchJournal(board: board(context(eight)))),
  ("undo", WatchJournal(board: board(context(three), [justLogged]), last: justLogged)),
  ("waiting", WatchJournal(board: board(context(three), waiting))),
  ("no-data", WatchJournal(board: board(nil))),
  ("signed-out", WatchJournal(board: board(.signedOut(day: today)))),
  ("no-habits", WatchJournal(board: board(context([])))),
  ("stale-day", WatchJournal(board: board(context(three, day: yesterday), [staleLog]))),
  ("focused", WatchJournal(board: board(context(eight)), focus: "snacks")),
] }

// The 45 mm and 40 mm screens, in points.
let sizes: [(String, CGSize)] = [("", CGSize(width: 198, height: 242)), ("-40mm", CGSize(width: 162, height: 197))]

// ImageRenderer draws neither a NavigationStack nor a ScrollView (both come out
// blank), so each view is hosted in an offscreen window and its layer drawn.
@MainActor func write<V: View>(_ view: V, size: CGSize, background: Color = .black, to name: String) {
  let framed =
    view
    .frame(width: size.width, height: size.height)
    .background(background)
    .environment(\.colorScheme, .dark)
  let host = NSHostingView(rootView: framed)
  host.frame = CGRect(origin: .zero, size: size)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
  window.appearance = NSAppearance(named: .darkAqua)
  window.contentView = host
  window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
  window.orderFrontRegardless()
  host.layoutSubtreeIfNeeded()
  RunLoop.main.run(until: Date().addingTimeInterval(0.4))
  host.layoutSubtreeIfNeeded()
  host.display()
  let scale: CGFloat = 2
  let pixels = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  pixels.size = size
  host.cacheDisplay(in: host.bounds, to: pixels)
  window.orderOut(nil)
  try! pixels.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
  print(name)
}

MainActor.assumeIsolated {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.prohibited)
  for (name, journal) in screens() {
    for (suffix, size) in sizes {
      write(HabitList(journal: journal), size: size, to: name + suffix)
    }
  }
  // Every row of the long list at once, to see each mark.
  write(HabitList(journal: screens()[1].1), size: CGSize(width: 198, height: 500), to: "today-8-all")
  let cigarettes = board(context(eight)).row("cigarettes")
  let snacks = board(context(eight)).row("snacks")
  for (suffix, row) in [("", cigarettes), ("-long", snacks), ("-none", nil)] {
    for (name, size, view) in complications(row) {
      write(view, size: size, to: "complication-\(name)\(suffix)")
    }
  }
}
