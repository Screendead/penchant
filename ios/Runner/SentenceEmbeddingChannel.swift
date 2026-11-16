import Foundation
import NaturalLanguage

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

// The Dart side is lib/notes/note_meaning.dart. Turns note text into vectors
// with Apple's on-device sentence embedding (iOS 14, macOS 11: both below the
// app's floors). Nothing is sent or kept: text in, vectors out, in memory.
// Errors never carry the text. The macOS app compiles this file too.
enum SentenceEmbeddingChannel {
  static let channelName = "com.screendead.penchant/sentence_embedding"
  private static let queue = DispatchQueue(label: "com.screendead.penchant.embedding", qos: .userInitiated)
  private static var loaded: NLEmbedding??

  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "available":
        queue.async {
          let ok = embedding() != nil
          DispatchQueue.main.async { result(ok) }
        }
      case "embed":
        guard let texts = call.arguments as? [String] else {
          result(FlutterError(code: "arguments", message: "expected a list of strings", details: nil))
          return
        }
        queue.async {
          let answer = embed(texts)
          DispatchQueue.main.async { result(answer) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // The device's first preferred language, loaded once; on the queue only.
  private static func embedding() -> NLEmbedding? {
    if let loaded { return loaded }
    let code = Locale.preferredLanguages.first.map { Locale(identifier: $0).languageCode ?? $0 } ?? "en"
    let found = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: code))
    loaded = .some(found)
    return found
  }

  private static func embed(_ texts: [String]) -> Any {
    guard let model = embedding() else {
      return FlutterError(code: "unavailable", message: "no sentence embedding for this language", details: nil)
    }
    return texts.map { text -> Any in
      guard let vector = model.vector(for: text) else { return NSNull() }
      let floats = vector.map { Float($0) }
      return floats.withUnsafeBufferPointer { FlutterStandardTypedData(float32: Data(buffer: $0)) }
    }
  }
}
