import CoreLocation
import Flutter
import Photos

// The Dart side is lib/insights/photos_source.dart, which turns runs of
// photos at one place into stays in the sealed device file `places`. Only
// each asset's creation date and location are read: never image or video
// data, never anything kept on disk here. Read once per request from the
// Places card; the library is never observed.
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
}
