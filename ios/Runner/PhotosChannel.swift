import CoreLocation
import Flutter
import Photos
import UIKit

// The Dart side is lib/insights/photos_source.dart, which turns runs of
// photos at one place into stays in the sealed device file `places`. The
// import (`read`) reads only each asset's creation date and location. `near`
// reads thumbnails of the photos at one place, only when the person opens
// that place to name it, held in memory and never kept or sent. Nothing is
// written to disk here, and the library is never observed.
enum PhotosChannel {
  static let channelName = "com.screendead.penchant/photos"
  private static var channel: FlutterMethodChannel?
  private static let queue = DispatchQueue(label: "com.screendead.penchant.photos", qos: .userInitiated)

  // Assets read between progress reports, each batch in its own autorelease
  // pool so a large library is never held at once.
  private static let batch = 2000

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    PhotosChannel.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result(access(PHPhotoLibrary.authorizationStatus(for: .readWrite)))
      case "requestAccess":
        // The handler runs off the main thread.
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
          DispatchQueue.main.async { result(access(status)) }
        }
      case "read":
        read(result: result)
      case "near":
        near(call.arguments as? [String: Any], result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func access(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "full"
    case .limited: return "limited"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "denied"
    }
  }

  // Four numbers a geotagged asset: creation time in microseconds since 1970,
  // latitude, longitude and horizontal accuracy in metres. Assets without a
  // date or a location give nothing. With limited access the fetch holds
  // only the assets the person shared.
  private static func read(result: @escaping FlutterResult) {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited else {
      result(FlutterStandardTypedData(float64: Data()))
      return
    }
    queue.async {
      let options = PHFetchOptions()
      // iCloud Shared Albums and synced assets are other people's or other
      // devices' photos: their places are not the person's.
      options.includeAssetSourceTypes = [.typeUserLibrary]
      let assets = PHAsset.fetchAssets(with: options)
      let total = assets.count
      var rows: [Double] = []
      var start = 0
      while start < total {
        let end = min(start + batch, total)
        autoreleasepool {
          assets.enumerateObjects(at: IndexSet(integersIn: start..<end), options: []) { asset, _, _ in
            guard let date = asset.creationDate, let location = asset.location else { return }
            let c = location.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { return }
            rows.append((date.timeIntervalSince1970 * 1e6).rounded())
            rows.append(c.latitude)
            rows.append(c.longitude)
            rows.append(location.horizontalAccuracy)
          }
        }
        let done = end
        DispatchQueue.main.async {
          PhotosChannel.channel?.invokeMethod("progress", arguments: [done, total])
        }
        start = end
      }
      let data = rows.withUnsafeBufferPointer { Data(buffer: $0) }
      DispatchQueue.main.async { result(FlutterStandardTypedData(float64: data)) }
    }
  }

  // Up to `limit` photos within `radius` metres of one point, newest first,
  // spread evenly across time so years of visits show, each as
  // {"at": microseconds since 1970, "jpeg": bytes}. Only photos already on the
  // device: none is downloaded from iCloud.
  private static func near(_ args: [String: Any]?, result: @escaping FlutterResult) {
    let none: [[String: Any]] = []
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    guard status == .authorized || status == .limited,
      let lat = (args?["lat"] as? NSNumber)?.doubleValue,
      let lon = (args?["lon"] as? NSNumber)?.doubleValue,
      let radius = (args?["radius"] as? NSNumber)?.doubleValue,
      let limit = (args?["limit"] as? NSNumber)?.intValue,
      let pixels = (args?["pixels"] as? NSNumber)?.intValue,
      CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)),
      radius > 0, limit > 0, pixels > 0
    else {
      result(none)
      return
    }
    queue.async {
      let centre = CLLocation(latitude: lat, longitude: lon)
      let options = PHFetchOptions()
      options.includeAssetSourceTypes = [.typeUserLibrary]
      let assets = PHAsset.fetchAssets(with: options)
      let total = assets.count
      var matches: [(date: Date, asset: PHAsset)] = []
      var start = 0
      while start < total {
        let end = min(start + batch, total)
        autoreleasepool {
          assets.enumerateObjects(at: IndexSet(integersIn: start..<end), options: []) { asset, _, _ in
            guard let date = asset.creationDate, let location = asset.location else { return }
            guard CLLocationCoordinate2DIsValid(location.coordinate) else { return }
            if location.distance(from: centre) <= radius { matches.append((date: date, asset: asset)) }
          }
        }
        start = end
      }
      matches.sort { $0.date > $1.date }
      let chosen: [(date: Date, asset: PHAsset)]
      if matches.count <= limit {
        chosen = matches
      } else if limit == 1 {
        chosen = [matches[0]]
      } else {
        let last = Double(matches.count - 1)
        chosen = (0..<limit).map { matches[Int((Double($0) * last / Double(limit - 1)).rounded())] }
      }
      let request = PHImageRequestOptions()
      request.isNetworkAccessAllowed = false
      request.isSynchronous = true
      // Calls the handler exactly once.
      request.deliveryMode = .highQualityFormat
      request.resizeMode = .fast
      let size = CGSize(width: pixels, height: pixels)
      var photos: [[String: Any]] = []
      for match in chosen {
        autoreleasepool {
          var jpeg: Data?
          PHImageManager.default().requestImage(
            for: match.asset, targetSize: size, contentMode: .aspectFill, options: request
          ) { image, _ in
            jpeg = image?.jpegData(compressionQuality: 0.8)
          }
          if let jpeg {
            photos.append([
              "at": Int64((match.date.timeIntervalSince1970 * 1e6).rounded()),
              "jpeg": FlutterStandardTypedData(bytes: jpeg),
            ])
          }
        }
      }
      DispatchQueue.main.async { result(photos) }
    }
  }
}
