import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// A night out on the Lock Screen (NightOut.swift). Anyone near the phone can
// read it, so unless the person chose otherwise it says "Tonight" in ink, not
// the habit's name or colour.
@available(iOS 17.0, *)
struct NightWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NightAttributes.self) { context in
      NightLockScreen(context: context)
        .activityBackgroundTint(Palette.bg)
        .activitySystemActionForegroundColor(Palette.text)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          NightLabel(context: context).padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          NightCount(context: context, size: 30).padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if !context.isStale {
            NightPlus(context: context).frame(maxWidth: .infinity, alignment: .trailing)
          }
        }
      } compactLeading: {
        NightMark(slot: context.attributes.slot, size: 10)
      } compactTrailing: {
        NightCount(context: context, size: 14)
      } minimal: {
        NightCount(context: context, size: 14)
      }
    }
  }
}

@available(iOS 17.0, *)
private struct NightLockScreen: View {
  let context: ActivityViewContext<NightAttributes>

  var body: some View {
    HStack(spacing: 14) {
      NightLabel(context: context)
      Spacer(minLength: 8)
      NightCount(context: context, size: 36)
      if !context.isStale {
        NightPlus(context: context)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

@available(iOS 17.0, *)
private struct NightLabel: View {
  let context: ActivityViewContext<NightAttributes>

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      NightMark(slot: context.attributes.slot, size: 12)
      VStack(alignment: .leading, spacing: 2) {
        Text(context.attributes.habit ?? "Tonight")
          .font(Typeface.display(18, .heavy))
          .foregroundStyle(Palette.text)
          .lineLimit(1)
        (Text(context.isStale ? "Ended · from " : "since ")
          + Text(context.attributes.start, format: .dateTime.hour().minute()))
          .font(Typeface.text(13))
          .foregroundStyle(Palette.muted)
          .lineLimit(1)
      }
    }
  }
}

// The habit's colour when shown, else an ink ring.
@available(iOS 17.0, *)
private struct NightMark: View {
  let slot: Int?
  let size: CGFloat

  var body: some View {
    if let slot {
      Circle().fill(Palette.fill(slot)).frame(width: size, height: size)
    } else {
      Circle().strokeBorder(Palette.text, lineWidth: 2).frame(width: size, height: size)
    }
  }
}

@available(iOS 17.0, *)
private struct NightCount: View {
  let context: ActivityViewContext<NightAttributes>
  let size: CGFloat

  var body: some View {
    Text(formatCount(context.state.count))
      .font(Typeface.mono(size, .semibold))
      .foregroundStyle(context.attributes.slot.map(Palette.ink) ?? Palette.text)
      .contentTransition(.numericText(value: context.state.count))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .accessibilityLabel("\(context.attributes.habit ?? "Tonight"), \(formatCount(context.state.count))")
  }
}

@available(iOS 17.0, *)
private struct NightPlus: View {
  let context: ActivityViewContext<NightAttributes>

  var body: some View {
    Button(intent: NightLogIntent(nightID: context.activityID)) {
      Text("+1")
        .font(Typeface.mono(18, .semibold))
        .foregroundStyle(Palette.text)
        .frame(width: 52, height: 52)
        .background(Circle().fill(Palette.surface2))
        .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(context.attributes.habit.map { "Log one of \($0)" } ?? "Log one")
  }
}
