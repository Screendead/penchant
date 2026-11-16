import SwiftUI

// The watch app's one screen: the iPhone's top habits with today's totals.
// A tap on a row logs one of that habit.
struct HabitList: View {
  @ObservedObject var journal: WatchJournal

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
    }
    .tint(WatchPalette.text)
  }

  @ViewBuilder private var content: some View {
    switch journal.board.state {
    case .noData:
      WatchNotice(
        title: "Open Penchant on your iPhone", detail: "Your habits show here once it has been opened.")
    case .signedOut:
      WatchNotice(title: "Sign in on your iPhone", detail: "Nobody is signed in to Penchant there.")
    case .habits where journal.board.rows.isEmpty:
      WatchNotice(title: "No habits yet", detail: "Add one in Penchant on your iPhone.")
    case .habits:
      rows
    }
  }

  private var rows: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 6) {
          ForEach(journal.board.rows) { row in
            Button {
              journal.log(row.habit)
            } label: {
              HabitRow(row: row, focused: journal.focus == row.id)
            }
            .buttonStyle(RowPress())
            .id(row.id)
            .accessibilityLabel("\(row.habit.name), \(watchCount(row.total)) \(row.unit) today")
            .accessibilityHint("Logs 1 \(row.habit.unitOne)")
          }
          footnotes
        }
        .padding(.horizontal, 2)
      }
      .safeAreaInset(edge: .bottom) {
        if let last = journal.last, let row = journal.board.row(last.viceID) {
          UndoBar(row: row, until: last.undoUntil) { journal.undo() }
            .id(last.id)
            // The bar leaves when its window ends.
            .task {
              let left = last.undoUntil.timeIntervalSinceNow
              try? await Task.sleep(nanoseconds: UInt64(max(0, left) * 1_000_000_000))
              journal.refresh()
            }
        }
      }
      .onChange(of: journal.focus, initial: true) { _, habit in
        guard let habit else { return }
        withAnimation { proxy.scrollTo(habit, anchor: .center) }
      }
      // The outline marks the habit the complication opened, for a moment.
      .task(id: journal.focus) {
        guard journal.focus != nil, (try? await Task.sleep(nanoseconds: 6_000_000_000)) != nil else { return }
        journal.focus = nil
      }
    }
  }

  @ViewBuilder private var footnotes: some View {
    if !journal.board.current {
      Footnote("Counting this watch's logs until your iPhone sends today's totals.")
    }
    if journal.board.waiting > 0 {
      Footnote(
        journal.board.waiting == 1
          ? "1 log is waiting for your iPhone." : "\(journal.board.waiting) logs are waiting for your iPhone.")
    }
  }
}

private struct HabitRow: View {
  let row: WatchBoard.Row
  let focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      WatchMark(habit: row.habit)
        .frame(width: 14, height: 14)
      VStack(alignment: .leading, spacing: 0) {
        Text(row.habit.name)
          .font(WatchType.text(16, .semibold))
          .foregroundStyle(WatchPalette.text)
          .lineLimit(1)
        Text(row.unit)
          .font(WatchType.text(12))
          .foregroundStyle(WatchPalette.muted)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(watchCount(row.total))
        .font(WatchType.mono(24, .semibold))
        .foregroundStyle(row.total > 0 ? WatchPalette.ink(row.habit.slot) : WatchPalette.muted)
        .contentTransition(.numericText())
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 48)
    .background(WatchPalette.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      if focused {
        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WatchPalette.text, lineWidth: 1.5)
      }
    }
  }
}

private struct RowPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.6 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
  }
}

// Paper on ink, the app's chrome: what was logged and its Undo, with the
// window running out along the bar's foot.
private struct UndoBar: View {
  let row: WatchBoard.Row
  let until: Date
  let undo: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var left: CGFloat = 1

  var body: some View {
    Button(action: undo) {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Logged 1 \(row.habit.unitOne)")
            .font(WatchType.text(12))
            .lineLimit(1)
          Text("Undo")
            .font(WatchType.text(16, .bold))
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 15, weight: .semibold))
      }
      .foregroundStyle(WatchPalette.onAccent)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(alignment: .bottomLeading) {
        GeometryReader { box in
          WatchPalette.onAccent.opacity(0.35)
            .frame(width: box.size.width * left, height: 3)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
      }
      .background(WatchPalette.text)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(RowPress())
    .padding(.horizontal, 2)
    .accessibilityLabel("Undo the log of 1 \(row.habit.unitOne) of \(row.habit.name)")
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: max(0, until.timeIntervalSinceNow))) { left = 0 }
    }
  }
}

private struct Footnote: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(WatchType.text(12))
      .foregroundStyle(WatchPalette.muted)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 6)
      .padding(.top, 4)
  }
}

private struct WatchNotice: View {
  let title: String
  let detail: String

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        Text(title)
          .font(WatchType.display(18, .bold))
          .foregroundStyle(WatchPalette.text)
        Text(detail)
          .font(WatchType.text(14))
          .foregroundStyle(WatchPalette.muted)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 6)
      .frame(maxWidth: .infinity)
    }
  }
}
