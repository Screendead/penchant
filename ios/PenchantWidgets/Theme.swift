import SwiftUI

#if os(macOS)
  import AppKit
  typealias PlatformColor = NSColor
#else
  import UIKit
  typealias PlatformColor = UIColor
#endif

// Copied from lib/design/tokens.json (Day Dial); the extension cannot read the
// Flutter bundle. A token change there is a change here.
enum Palette {
  static let bg = dynamic(0xF6F4EF, 0x151412)
  static let surface = dynamic(0xFFFFFF, 0x1F1D1B)
  static let surface2 = dynamic(0xEFECE5, 0x2A2825)
  static let text = dynamic(0x1D1C1A, 0xF3F0EA)
  static let muted = dynamic(0x635E56, 0xACA79D)
  static let line = dynamic(0x1D1C1A, 0xF3F0EA, lightAlpha: 0x1A, darkAlpha: 0x1F)
  static let spoke = dynamic(0x1D1C1A, 0xF3F0EA, lightAlpha: 0x80, darkAlpha: 0x80)

  static let data: [Color] = [
    dynamic(0xFFB347, 0xFFB347),
    dynamic(0xFF7A59, 0xFF7A59),
    dynamic(0xE8505B, 0xE95963),
    dynamic(0x9B5DE5, 0xA973E9),
    dynamic(0x4D96FF, 0x4D96FF),
  ]
  static let ink: [Color] = [
    dynamic(0x8F5600, 0xFFB347),
    dynamic(0xB03E1C, 0xFF7A59),
    dynamic(0xB42A37, 0xF0737C),
    dynamic(0x6A31B5, 0xB48AF0),
    dynamic(0x1D5FC2, 0x4D96FF),
  ]

  static func fill(_ slot: Int) -> Color { data[((slot % 5) + 5) % 5] }
  static func ink(_ slot: Int) -> Color { ink[((slot % 5) + 5) % 5] }

  private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: UInt32 = 0xFF, darkAlpha: UInt32 = 0xFF)
    -> Color
  {
    #if os(macOS)
      Color(
        NSColor(name: nil) { appearance in
          appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? uiColor(dark, darkAlpha) : uiColor(light, lightAlpha)
        })
    #else
      Color(
        UIColor { traits in
          traits.userInterfaceStyle == .dark ? uiColor(dark, darkAlpha) : uiColor(light, lightAlpha)
        })
    #endif
  }

  private static func uiColor(_ rgb: UInt32, _ alpha: UInt32) -> PlatformColor {
    PlatformColor(
      red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(alpha) / 255)
  }
}

// The Red Hat variable fonts, bundled with the extension (UIAppFonts on iOS,
// ATSApplicationFontsPath on macOS).
enum Typeface {
  static func display(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
    .custom("Red Hat Display", size: size).weight(weight)
  }
  static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Red Hat Text", size: size).weight(weight)
  }
  static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .custom("Red Hat Mono", size: size).weight(weight).monospacedDigit()
  }
}
