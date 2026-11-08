import SwiftUI
import WidgetKit

@main
struct PenchantWidgetsBundle: WidgetBundle {
  var body: some Widget {
    LastWeekWidget()
    LogWidget()
    #if os(iOS)
      if #available(iOS 18.0, *) {
        LogControl()
      }
    #endif
  }
}
