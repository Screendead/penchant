import 'package:flutter/services.dart';

/// Copies a secret so it stays on this device and expires: a local-only,
/// expiring pasteboard item on iOS; on macOS one marked concealed and
/// transient, cleared after [lifetime] if the pasteboard still holds it.
/// Native side: `SecretPasteboard` in ios/Runner/AppDelegate.swift and
/// macos/Runner/MainFlutterWindow.swift.
class SecretClipboard {
  const SecretClipboard([this._channel = const MethodChannel(channelName)]);

  static const String channelName = 'com.screendead.penchant/secret_clipboard';
  static const Duration lifetime = Duration(minutes: 2);

  final MethodChannel _channel;

  /// Never falls back to a plain clipboard write, which would sync to the
  /// user's other devices and stay; throws instead. Errors never carry [text].
  Future<void> copy(String text) async {
    try {
      await _channel.invokeMethod<void>('copy', <String, Object>{
        'text': text,
        'seconds': lifetime.inSeconds,
      });
    } on Object {
      throw const SecretClipboardException();
    }
  }
}

class SecretClipboardException implements Exception {
  const SecretClipboardException();

  @override
  String toString() => 'SecretClipboardException: the copy failed';
}
