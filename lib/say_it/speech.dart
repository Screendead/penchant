import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The Swift side is ios/Runner/SpeechChannel.swift: Apple's Speech framework
// with requiresOnDeviceRecognition, so the recording is never sent anywhere.
// Only the words come back over the channel.

abstract interface class SpeechSource {
  /// True only when this locale can be recognised on this device.
  Future<bool> available();

  /// Asks for speech recognition and the microphone where not yet answered.
  /// True when both are granted.
  Future<bool> requestAccess();

  /// The words so far, each time they change, until [stop] or a pause ends
  /// the recognition; then closes. An error means it could not listen.
  Stream<String> listen();

  Future<void> stop();
}

class ChannelSpeechSource implements SpeechSource {
  ChannelSpeechSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.screendead.penchant/speech') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  StreamController<String>? _words;

  Future<Object?> _handle(MethodCall call) async {
    final StreamController<String>? words = _words;
    if (words == null) return null;
    final Object? args = call.arguments;
    final Object? text = args is Map ? args['text'] : null;
    switch (call.method) {
      case 'partial':
        if (text is String) words.add(text);
      case 'ended':
        if (text is String) words.add(text);
        final Object? error = args is Map ? args['error'] : null;
        if (error is String) words.addError(SpeechFailed(error));
        _words = null;
        await words.close();
    }
    return null;
  }

  @override
  Future<bool> available() async =>
      await _channel.invokeMethod<bool>('available') ?? false;

  @override
  Future<bool> requestAccess() async =>
      await _channel.invokeMethod<bool>('requestAccess') ?? false;

  @override
  Stream<String> listen() {
    unawaited(_words?.close());
    final StreamController<String> words = StreamController<String>();
    _words = words;
    _channel.invokeMethod<void>('start').catchError((Object e) {
      if (identical(_words, words)) {
        _words = null;
        words
          ..addError(e)
          ..close();
      }
    });
    return words.stream;
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// Why listening stopped: `denied`, `unavailable`, `audio` or `recognition`.
class SpeechFailed implements Exception {
  const SpeechFailed(this.reason);

  final String reason;

  @override
  String toString() => 'SpeechFailed($reason)';
}

/// Null off iOS: the Mac has no channel, and typing works everywhere.
final Provider<SpeechSource?> speechSourceProvider = Provider<SpeechSource?>(
  (Ref ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? ChannelSpeechSource()
      : null,
);

/// Whether to offer the microphone: false off iOS, where on-device
/// recognition is missing for the locale, or when asking fails.
final speechAvailableProvider =
    FutureProvider.autoDispose<bool>((Ref ref) async {
      final SpeechSource? source = ref.watch(speechSourceProvider);
      if (source == null) return false;
      try {
        return await source.available();
      } catch (_) {
        return false;
      }
    });
