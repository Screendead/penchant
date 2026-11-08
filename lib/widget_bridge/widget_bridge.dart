import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/data/widget_snapshot.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/data/queued_log.dart';

// Hands the snapshot to ios/Runner/WidgetBridge.swift, which keeps it in the
// App Group and reloads the widgets' timelines.
class WidgetBridge {
  const WidgetBridge([
    this._channel = const MethodChannel('com.screendead.penchant/widgets'),
  ]);

  final MethodChannel _channel;

  Future<void> save(String snapshot) => _invoke('save', snapshot);

  Future<void> clear() => _invoke('clear');

  /// The logs the widgets, controls and intents left for the app to write.
  Future<List<QueuedLog>> pendingLogs() async {
    try {
      return decodeQueuedLogs(
        await _channel.invokeMethod<String>('pendingLogs') ?? '[]',
      );
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while reading the widget log queue');
      return const <QueuedLog>[];
    }
  }

  Future<void> removeLogs(List<QueuedLog> done) => _invoke(
    'removeLogs',
    jsonEncode(<Object?>[for (final l in done) l.toJson()]),
  );

  Future<void> _invoke(String method, [Object? argument]) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on PlatformException catch (e, stack) {
      reportError(e, stack, context: 'while updating the widgets');
    }
  }
}

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => const WidgetBridge(),
);

bool get widgetsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

// Waits for a burst of snapshots (every write and its acknowledgement) to
// settle before writing once.
const Duration widgetSnapshotSettle = Duration(milliseconds: 500);

// Keeps the widgets' snapshot current while the app runs: on every change to
// the vices or the last 30 days, and on resume. Signing out, or another
// account signing in, clears it first, so one account's habit names never
// show under another.
final widgetSyncProvider = Provider<void>((ref) {
  if (!widgetsSupported) {
    return;
  }
  final _SyncMemory memory = ref.watch(_syncMemoryProvider);
  final WidgetBridge bridge = ref.watch(widgetBridgeProvider);
  final AsyncValue<User?> user = ref.watch(userProvider);
  if (!user.hasValue) {
    return;
  }
  final String? uid = user.value?.uid;
  // A launch signed out clears what a session that ended without signing
  // out (the app killed, say) may have left.
  if (memory.seenUser ? uid != memory.uid : uid == null) {
    memory
      ..latest = null
      ..written = null;
    unawaited(bridge.clear());
  }
  memory
    ..seenUser = true
    ..uid = uid;
  if (uid == null) {
    return;
  }

  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: () => memory.write(bridge, force: true),
  );
  ref.onDispose(lifecycle.dispose);

  final DateTime today = ref.watch(todayProvider);
  final List<Vice>? vices = ref.watch(viceListForUserProvider(uid)).value;
  final List<ViceActivity>? activities = ref
      .watch(
        viceActivityRecentForUserProvider((
          uid: uid,
          today: today,
          days: widgetTopWindowDays,
        )),
      )
      .value;
  if (vices == null || activities == null) {
    return;
  }
  memory.latest = jsonEncode(
    widgetSnapshot(
      uid: uid,
      vices: vices,
      activities: activities,
      today: today,
    ),
  );
  final Timer settle = Timer(widgetSnapshotSettle, () => memory.write(bridge));
  ref.onDispose(settle.cancel);
});

// What widgetSyncProvider must remember across its rebuilds.
final _syncMemoryProvider = Provider<_SyncMemory>((ref) => _SyncMemory());

class _SyncMemory {
  String? uid;
  bool seenUser = false;
  String? written;
  String? latest;

  void write(WidgetBridge bridge, {bool force = false}) {
    final String? snapshot = latest;
    if (snapshot == null || (!force && snapshot == written)) {
      return;
    }
    written = snapshot;
    unawaited(bridge.save(snapshot));
  }
}
