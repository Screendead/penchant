import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA time zone as last read, for each new entry to store:
/// null until the first read answers, or when it fails. Read at launch and
/// on each resume (the zone may change while travelling), never at log time,
/// so a log never waits on the channel. MyApp keeps it alive.
final NotifierProvider<LogZone, String?> logZoneProvider =
    NotifierProvider<LogZone, String?>(LogZone.new);

class LogZone extends Notifier<String?> {
  /// Replaced by tests, which have no platform channel.
  static Future<String?> Function() read = _readDevice;

  // No timeout: nothing waits on the answer, since a log reads the state
  // as it stands.
  static Future<String?> _readDevice() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  @override
  String? build() {
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: _refresh,
    );
    ref.onDispose(lifecycle.dispose);
    _refresh();
    return null;
  }

  Future<void> _refresh() async {
    try {
      final String? zone = await read();
      if (ref.mounted && zone != null && zone.isNotEmpty) state = zone;
    } catch (_) {
      // Unknown: entries logged meanwhile store no zone.
    }
  }
}
