import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which biometric the device offers before its passcode.
enum Biometry { faceID, touchID, none }

/// Whether the device can ask for its owner at all (it cannot without a
/// passcode), and how.
class DeviceAuthStatus {
  const DeviceAuthStatus({required this.available, required this.biometry});

  final bool available;
  final Biometry biometry;
}

enum AuthOutcome { success, cancelled, unavailable, failed }

/// Face ID, Touch ID or the device passcode, through LocalAuthentication's
/// device-owner policy, so biometrics fall back to the passcode.
/// Native side: `DeviceAuth` in ios/Runner/AppDelegate.swift and
/// macos/Runner/MainFlutterWindow.swift.
class DeviceAuth {
  const DeviceAuth([this._channel = const MethodChannel(channelName)]);

  static const String channelName = 'com.screendead.penchant/device_auth';

  final MethodChannel _channel;

  Future<DeviceAuthStatus> status() async {
    final Map<Object?, Object?>? reply = await _channel
        .invokeMapMethod<Object?, Object?>('status');
    return DeviceAuthStatus(
      available: reply?['available'] == true,
      biometry: switch (reply?['biometry']) {
        'faceID' => Biometry.faceID,
        'touchID' => Biometry.touchID,
        _ => Biometry.none,
      },
    );
  }

  Future<AuthOutcome> authenticate(String reason) async {
    final String? outcome = await _channel.invokeMethod<String>(
      'authenticate',
      <String, Object>{'reason': reason},
    );
    return switch (outcome) {
      'success' => AuthOutcome.success,
      'cancelled' => AuthOutcome.cancelled,
      'unavailable' => AuthOutcome.unavailable,
      _ => AuthOutcome.failed,
    };
  }
}

final deviceAuthProvider = Provider<DeviceAuth>(
  (Ref ref) => const DeviceAuth(),
);

/// The way in, as the lock screen's button and Settings name it.
String unlockMethod(Biometry biometry) => switch (biometry) {
  Biometry.faceID => 'Face ID',
  Biometry.touchID => 'Touch ID',
  Biometry.none => 'passcode',
};

/// Read when Settings opens; a failed read names the passcode.
final deviceAuthStatusProvider = FutureProvider.autoDispose<DeviceAuthStatus>(
  (Ref ref) => ref.read(deviceAuthProvider).status(),
);
