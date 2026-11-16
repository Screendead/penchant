import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The Swift side is ios/Runner/LabelChannel.swift: the system camera or
// photo picker, then Vision's text recognition, all on the device. Only the
// recognised lines cross the channel; the photo stays in Swift's memory for
// the read and is gone after it. Nothing here keeps, logs or sends the lines,
// and no failure carries them.

enum LabelPhoto { camera, library }

enum LabelScanStatus { read, cancelled, noCamera, failed }

typedef LabelScan = ({LabelScanStatus status, List<String> lines});

abstract interface class LabelSource {
  /// Asks for a photo and reads its text. Never throws.
  Future<LabelScan> scan(LabelPhoto from);
}

class ChannelLabelSource implements LabelSource {
  ChannelLabelSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.screendead.penchant/label');

  final MethodChannel _channel;

  static const LabelScan _failed = (
    status: LabelScanStatus.failed,
    lines: <String>[],
  );

  @override
  Future<LabelScan> scan(LabelPhoto from) async {
    final Map<Object?, Object?>? answer;
    try {
      answer = await _channel.invokeMapMethod<Object?, Object?>(
        'read',
        <String, String>{'source': from.name},
      );
    } on Object {
      return _failed;
    }
    final LabelScanStatus? status = LabelScanStatus.values
        .where((LabelScanStatus s) => s.name == answer?['status'])
        .firstOrNull;
    if (status == null) return _failed;
    final Object? lines = answer?['lines'];
    return (
      status: status,
      lines: <String>[if (lines is List<Object?>) ...lines.whereType<String>()],
    );
  }
}

/// The label reader; null everywhere but iOS, so the Mac shows no camera.
final labelSourceProvider = Provider<LabelSource?>(
  (ref) =>
      defaultTargetPlatform == TargetPlatform.iOS ? ChannelLabelSource() : null,
);
