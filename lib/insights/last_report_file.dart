import 'dart:typed_data';

import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/insights/report_codec.dart';
import 'package:tracker/providers/insights_provider.dart';

/// The last Insights view with a computed report, one sealed file, shown at
/// the next cold open while the page reads everything again.
class LastReportFile {
  LastReportFile(this._files);

  final SealedFiles _files;

  // Loads, deletes and saves in order, so a delete after a bad read can never
  // remove a file a later save wrote.
  Future<void> _queue = Future<void>.value();

  static const String name = 'last-report';

  String get uid => _files.uid;

  /// Null when absent or unreadable, which is deleted. Never throws.
  Future<InsightsView?> load() {
    final Future<InsightsView?> got = _queue.then((_) async {
      final Uint8List? bytes = await _files.read(name);
      if (bytes == null) return null;
      final InsightsView? view = decodeInsightsView(bytes);
      if (view == null) await _files.delete(name);
      return view;
    });
    _queue = got.then((_) {}, onError: (Object _) {});
    return got.then((InsightsView? v) => v, onError: (Object _) => null);
  }

  /// Keeps [view] when it holds a computed report. Never throws.
  Future<void> save(InsightsView view) => _queue = _queue
      .then((_) async {
        final Uint8List? bytes = encodeInsightsView(view);
        if (bytes != null) await _files.write(name, bytes);
      })
      .catchError((Object _) {});
}
