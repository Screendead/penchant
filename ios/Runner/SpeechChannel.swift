import AVFoundation
import Flutter
import Speech

// The Dart side is lib/say_it/speech.dart. Recognition runs on this device
// only (requiresOnDeviceRecognition): where the locale has no on-device model,
// "available" answers false and nothing listens. The recording is never kept
// or sent; only its words cross the channel, as "partial" while listening and
// "ended" once, with an error code when it failed.
enum SpeechChannel {
  static let channelName = "com.screendead.penchant/speech"
  private static var channel: FlutterMethodChannel?
  private static let engine = AVAudioEngine()
  private static var request: SFSpeechAudioBufferRecognitionRequest?
  private static var task: SFSpeechRecognitionTask?
  private static var lastText = ""

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "available":
        result(recognizer()?.supportsOnDeviceRecognition ?? false)
      case "requestAccess":
        requestAccess { granted in DispatchQueue.main.async { result(granted) } }
      case "start":
        result(nil)
        start()
      case "stop":
        stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func recognizer() -> SFSpeechRecognizer? {
    SFSpeechRecognizer(locale: Locale.current)
  }

  private static func requestAccess(_ done: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else { return done(false) }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in done(granted) }
    }
  }

  private static func send(_ method: String, _ text: String, error: String? = nil) {
    var args: [String: Any] = ["text": text]
    if let error { args["error"] = error }
    DispatchQueue.main.async { channel?.invokeMethod(method, arguments: args) }
  }

  private static func start() {
    finish(error: nil, notify: false)
    guard SFSpeechRecognizer.authorizationStatus() == .authorized,
      AVAudioSession.sharedInstance().recordPermission == .granted
    else { return send("ended", "", error: "denied") }
    guard let recognizer = recognizer(), recognizer.supportsOnDeviceRecognition,
      recognizer.isAvailable
    else { return send("ended", "", error: "unavailable") }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    if #available(iOS 16.0, *) { request.addsPunctuation = true }
    self.request = request
    lastText = ""

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
      }
      engine.prepare()
      try engine.start()
    } catch {
      return finish(error: "audio", notify: true)
    }

    task = recognizer.recognitionTask(with: request) { result, error in
      if let result {
        lastText = result.bestTranscription.formattedString
        if result.isFinal {
          return finish(error: nil, notify: true)
        }
        send("partial", lastText)
      }
      if error != nil {
        // A stop before any words also ends with an error; the words so far
        // are still the answer.
        finish(error: lastText.isEmpty ? "recognition" : nil, notify: true)
      }
    }
  }

  private static func stop() {
    // Ending the audio lets the recognizer give its final words.
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
  }

  private static func finish(error: String?, notify: Bool) {
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
    task?.cancel()
    let hadTask = task != nil || request != nil
    task = nil
    request = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    if notify && hadTask {
      send("ended", lastText, error: error)
    } else if notify && error != nil {
      send("ended", lastText, error: error)
    }
  }
}
