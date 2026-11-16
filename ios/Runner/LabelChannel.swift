import Flutter
import PhotosUI
import UIKit
import Vision

// The Dart side is lib/label/label_source.dart. The person takes a photo of a
// drink's label or picks one; Vision reads its text on this device and only
// the lines of text cross the channel. The photo is held in memory for the
// read and never written to disk or sent anywhere. The system pickers need no
// photo library access: PHPicker hands over only the photo picked.
enum LabelChannel {
  static let channelName = "com.screendead.penchant/label"
  // The picker in front, kept alive until it answers.
  private static var pending: LabelPick?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "read":
        let source = (call.arguments as? [String: Any])?["source"] as? String
        read(camera: source == "camera", result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func host() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private static func read(camera: Bool, result: @escaping FlutterResult) {
    guard pending == nil, let host = host() else {
      result(["status": "failed"])
      return
    }
    let pick = LabelPick { image in
      pending = nil
      guard let image = image else {
        result(["status": "cancelled"])
        return
      }
      recognise(image, result: result)
    }
    if camera {
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
        result(["status": "noCamera"])
        return
      }
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = pick
      pending = pick
      host.present(picker, animated: true)
    } else {
      // No photo library given: the picker runs out of process and returns
      // only the picked item, with no asset identifier or access prompt.
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = pick
      pending = pick
      host.present(picker, animated: true)
    }
  }

  private static func recognise(_ image: UIImage, result: @escaping FlutterResult) {
    guard let cgImage = image.cgImage else {
      result(["status": "failed"])
      return
    }
    let orientation = orientationOf(image.imageOrientation)
    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      // Language correction would turn a misread figure into a word, or a
      // word into another; the Dart parser takes characters as read.
      request.usesLanguageCorrection = false
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
      var lines: [String] = []
      var failed = false
      do {
        try handler.perform([request])
        lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
      } catch {
        failed = true
      }
      DispatchQueue.main.async {
        result(failed ? ["status": "failed"] : ["status": "read", "lines": lines])
      }
    }
  }

  private static func orientationOf(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .left: return .left
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

// Answers once, with the picked or taken image or nil, after its picker has
// been dismissed.
final class LabelPick: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate,
  PHPickerViewControllerDelegate
{
  private let done: (UIImage?) -> Void

  init(done: @escaping (UIImage?) -> Void) {
    self.done = done
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    let image = info[.originalImage] as? UIImage
    picker.dismiss(animated: true) { self.done(image) }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true) { self.done(nil) }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true) {
      guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self)
      else {
        self.done(nil)
        return
      }
      // Loaded as an object in memory, not a file representation on disk.
      provider.loadObject(ofClass: UIImage.self) { object, _ in
        DispatchQueue.main.async { self.done(object as? UIImage) }
      }
    }
  }
}
