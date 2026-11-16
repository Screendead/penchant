import AppIntents

#if os(iOS)
  import Flutter
#endif

// Siri, Shortcuts, Spotlight and the Action button (r10-intents A). The
// log intent is ios/PenchantWidgets/LogIntents.swift, compiled into this
// target too, since App Shortcuts are read from the app's bundle.
@available(iOS 17.0, macOS 14.0, *)
struct PenchantShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogOneIntent(),
      phrases: [
        "Log \(\.$habit) in \(.applicationName)",
        "Log one in \(.applicationName)",
      ],
      shortTitle: "Log one",
      systemImageName: "plus.circle")
    #if os(iOS)
      // A phrase may name only an entity or enum parameter, and must name the
      // app, so Siri asks for the question once the phrase is heard.
      AppShortcut(
        intent: AskJournalIntent(),
        phrases: [
          "Ask \(.applicationName)",
          "Ask my journal in \(.applicationName)",
          "Ask \(.applicationName) a question",
        ],
        shortTitle: "Ask your journal",
        systemImageName: "text.bubble")
    #endif
  }
}

#if os(iOS)
  // Opens the app on Ask with the question asked (lib/ask/ask_from_siri.dart).
  // Declared in the app target only: an intent that opens the app is an error
  // in an extension.
  @available(iOS 17.0, *)
  struct AskJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask your journal"
    static let description = IntentDescription(
      "Opens Penchant's Ask page and asks your question there.")

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask your journal?")
    var question: String

    init() {}

    static var parameterSummary: some ParameterSummary {
      Summary("Ask \(\.$question)")
    }

    func perform() async throws -> some IntentResult {
      let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
      if asked.isEmpty { throw $question.needsValueError("What would you like to ask your journal?") }
      guard asked.utf16.count <= AskQuestion.maxLength else { throw AskQuestionError.tooLong }
      await AskQuestion.received(asked)
      return .result()
    }
  }

  // Apple's pattern for an intent that must also open the app before iOS 26
  // (AppIntent.openAppWhenRun).
  @available(iOS 17.0, *)
  @available(*, deprecated)
  extension AskJournalIntent {
    static var openAppWhenRun: Bool { true }
  }

  @available(iOS 17.0, *)
  enum AskQuestionError: Error, CustomLocalizedStringResourceConvertible {
    case tooLong

    var localizedStringResource: LocalizedStringResource {
      "That question is too long. Ask takes up to 300 characters."
    }
  }

  // Kept in memory until Dart takes it, since the intent can run before the
  // engine does; never written anywhere, as it is the person's own words.
  @MainActor
  enum AskQuestion {
    static let channelName = "com.screendead.penchant/ask_question"
    // CallableAskJournal.maxQuestion, in UTF-16 units as Dart counts.
    nonisolated static let maxLength = 300
    private static var channel: FlutterMethodChannel?
    private static var pending: String?

    static func register(with registrar: FlutterPluginRegistrar) {
      let appChannel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
      appChannel.setMethodCallHandler { call, result in
        guard call.method == "take" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let taken = pending
        pending = nil
        result(taken)
      }
      channel = appChannel
    }

    static func received(_ question: String) {
      pending = question
      channel?.invokeMethod("changed", arguments: nil)
    }
  }
#endif
