import 'package:flutter/foundation.dart';

/// Where each stage's duration goes: the device log. Only the stage's name,
/// its duration and counts, never a value read.
void Function(String line) insightsTimingLog = debugPrint;

Future<T> timedInsightsStage<T>(String stage, Future<T> Function() run) async {
  final Stopwatch watch = Stopwatch()..start();
  try {
    return await run();
  } finally {
    insightsTimingLog('Insights $stage: ${watch.elapsedMilliseconds} ms');
  }
}
