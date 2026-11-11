import 'package:flutter/services.dart';

/// Copies a secret so it expires: a local-only, expiring pasteboard item on
/// iOS. macOS has no local-only item, so there Universal Clipboard still
/// carries it to the user's other devices; it is marked concealed and
/// transient for clipboard managers and cleared after [lifetime] if the
/// pasteboard still holds it.
/// Native side: `SecretPasteboard` in ios/Runner/AppDelegate.swift and
/// macos/Runner/MainFlutterWindow.swift.
class SecretClipboard {
  const SecretClipboard([this._channel = const MethodChannel(channelName)]);

  static const String channelName = 'com.screendead.penchant/secret_clipboard';
  static const Duration lifetime = Duration(minutes: 2);

  final MethodChannel _channel;

  /// Never falls back to a plain clipboard write, which would stay; throws
  /// instead. Errors never carry [text].
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
