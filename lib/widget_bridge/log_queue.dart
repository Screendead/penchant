import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';
import 'package:tracker/writes/tracker_writes.dart';

const String widgetLogWhat = 'a log from a widget or Shortcut';

/// What a flush left queued: when a held-back log comes due, and whether a
/// log stayed because the server refused it or had not acknowledged it.
typedef FlushLeft = ({DateTime? next, bool refused, bool unacknowledged});

/// Writes [uid]'s ready logs through [writes], then takes them off the queue.
/// Each is removed once [RejectedWrites.settle] has journalled it and the
/// server answered or the write timed out into the SDK's own queue, so a
/// launch that ends first leaves it to the next flush, which writes the same
/// document again.
///
/// With [inBackground] (a headless engine whose process ends soon after) a log
/// the server refuses stays for the app's next flush to show in its banner,
/// since a background engine has no banner. So does a log the server has not
/// acknowledged, for the next flush to write again: the SDK's queue of an
/// exited process sends it only when Penchant next starts. So does a delete,
/// which a background flush sends only once it has seen the entry still on
/// the server, after the SDK's queued writes (an earlier run's copy of it
/// included) have drained: the rules refuse a repeat delete.
///
/// Without the journal key [writes] cannot create, so every log stays queued
/// for a flush that has it, and counts as unacknowledged.
///
/// [writeNow] names logs to write inside their Undo hold (readyLogs).
Future<FlushLeft> flushQueuedLogs({
  required WidgetBridge bridge,
  required TrackerWrites writes,
  required RejectedWrites rejected,
  required String uid,
  required DateTime now,
  bool inBackground = false,
  Set<String> writeNow = const <String>{},
}) async {
  final ({List<QueuedLog> ready, List<QueuedLog> cancelled, DateTime? next})
  batch = readyLogs(
    await bridge.pendingLogs(),
    uid: uid,
    now: now,
    writeNow: writeNow,
  );
  final List<QueuedLog> done = <QueuedLog>[...batch.cancelled];
  final List<QueuedLog> writable = <QueuedLog>[
    for (final QueuedLog log in batch.ready)
      if (writes.canCreate || log.op != QueuedLogOp.log) log,
  ];
  bool refused = false;
  bool unacknowledged = writable.length < batch.ready.length;
  await Future.wait(<Future<void>>[
    for (final QueuedLog log in writable)
      _write(log, writes, rejected, inBackground: inBackground).then((
        _Written written,
      ) {
        switch (written) {
          case _Written.done:
            done.add(log);
          case _Written.refused:
            refused = true;
          case _Written.unacknowledged:
            unacknowledged = true;
        }
      }),
  ]);
  if (done.isNotEmpty) {
    await bridge.removeLogs(done);
  }
  return (next: batch.next, refused: refused, unacknowledged: unacknowledged);
}

// done: the log can leave the queue.
enum _Written { done, refused, unacknowledged }

Future<_Written> _write(
  QueuedLog log,
  TrackerWrites writes,
  RejectedWrites rejected, {
  required bool inBackground,
}) async {
  if (inBackground && log.op == QueuedLogOp.delete) {
    switch (await _stillOnServer(log, writes)) {
      case false:
        return _Written.done;
      case null:
        return _Written.unacknowledged;
      case true:
        break;
    }
  }
  final SentWrite write = switch (log.op) {
    QueuedLogOp.log => writes.recordActivity(
      log.id,
      ownerID: log.uid,
      viceID: log.viceID,
      quantity: defaultQuantity,
      createdAt: log.createdAt,
      loggedVia: LoggedVia.widget,
    ),
    QueuedLogOp.delete => writes.deleteActivity(log.id),
  };
  final bool creates = log.op == QueuedLogOp.log;
  final String what = creates
      ? 'Not saved: $widgetLogWhat'
      : 'Not undone: $widgetLogWhat';
  try {
    final bool acknowledged = await rejected.settle(write, what);
    return acknowledged || !inBackground
        ? _Written.done
        : _Written.unacknowledged;
  } on FirebaseException catch (e, stack) {
    // Refused (a habit deleted since the tap, say): writing it again would
    // be refused again, so it goes to the banner and leaves the queue.
    reportError(e, stack, context: 'while writing $widgetLogWhat');
    if (inBackground) {
      return _Written.refused;
    }
    rejected.reporter(
      what,
      creates: creates ? log.id : null,
      changes: creates ? null : log.id,
    )(e);
    return _Written.done;
  }
}

// Whether the entry a queued delete names is on the server, or null when
// that cannot be learnt in time (offline, say).
Future<bool?> _stillOnServer(QueuedLog log, TrackerWrites writes) async {
  try {
    await writes.waitForPendingWrites().timeout(writeTimeout);
    return await writes
            .serverDocument('activities', log.id, ownerID: log.uid)
            .timeout(writeTimeout) !=
        null;
  } on Object {
    return null;
  }
}

/// Runs the app's flushes of the widget queue one at a time.
class WidgetLogFlusher {
  WidgetLogFlusher._(this._run);

  final Future<void> Function(Set<String> writeNow) _run;
  bool _disposed = false;
  Future<void>? _inFlight;

  /// A request during a flush waits for that one rather than starting another.
  Future<void> flush() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _inFlight ??= _start(const <String>{});
  }

  /// Writes the log [activityID] now, inside its Undo hold, after any flush
  /// already running (which may have read the queue before it was there).
  /// Once this completes the log is off the queue, written, or still queued
  /// because it could not be: no later flush creates it again, so nothing
  /// can overwrite a change made to the entry after this.
  Future<void> writeNow(String activityID) async {
    while (_inFlight != null) {
      await _inFlight;
    }
    if (_disposed) {
      return;
    }
    return _inFlight = _start(<String>{activityID});
  }

  Future<void> _start(Set<String> writeNow) =>
      _run(writeNow).whenComplete(() => _inFlight = null);

  void _dispose() => _disposed = true;
}

/// Writes the widgets' queued logs while someone is signed in with the journal
/// key loaded: at once, on every resume, when a held-back log comes due, and
/// when native asks (a log queued while the app runs, or a background
/// refresh). Nothing polls: native hears each enqueue from the extension.
/// Null while it cannot write.
final widgetLogFlushProvider = Provider<WidgetLogFlusher?>((ref) {
  if (!widgetsSupported) {
    return null;
  }
  final String? uid = ref.watch(
    userProvider.select((AsyncValue<User?> u) => u.value?.uid),
  );
  if (uid == null) {
    return null;
  }
  // Until the key loads (or while it is missing or locked) TrackerWrites has
  // no sealer and cannot create. The queue keeps the logs, and the sealer
  // arriving rebuilds this provider.
  if (ref.watch(sealerProvider) == null) {
    return null;
  }
  final WidgetBridge bridge = ref.watch(widgetBridgeProvider);
  final TrackerWrites writes = ref.watch(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);

  bool disposed = false;
  Timer? due;
  late final WidgetLogFlusher flusher;
  Future<void> run(Set<String> writeNow) async {
    try {
      final DateTime? next = (await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: rejected,
        uid: uid,
        now: DateTime.now(),
        writeNow: writeNow,
      )).next;
      due?.cancel();
      if (next != null && !disposed) {
        due = Timer(next.difference(DateTime.now()), flusher.flush);
      }
    } on Object catch (e, stack) {
      reportError(e, stack, context: 'while flushing $widgetLogWhat');
    }
  }

  flusher = WidgetLogFlusher._(run);
  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: flusher.flush,
  );
  bridge.onFlushRequest(flusher.flush);
  ref.onDispose(() {
    disposed = true;
    flusher._dispose();
    due?.cancel();
    bridge.onFlushRequest(null);
    lifecycle.dispose();
  });
  unawaited(flusher.flush());
  return flusher;
});
