import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/writes/log_one.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/tracker_writes.dart';

const String widgetLogWhat = 'a log from a widget or Shortcut';

/// Writes [uid]'s ready logs through [writes], then takes them off the queue.
/// Each is removed once [RejectedWrites.settle] has journalled it and the
/// server answered or the write timed out into the SDK's own queue, so a
/// launch that ends first leaves it to the next flush, which writes the same
/// document again. Returns when to look again, if a log was held back.
///
/// With [keepRefused] a log the server refuses stays queued, for the app's
/// next flush to show in its banner: a background engine has no banner.
Future<DateTime?> flushQueuedLogs({
  required WidgetBridge bridge,
  required TrackerWrites writes,
  required RejectedWrites rejected,
  required String uid,
  required DateTime now,
  bool keepRefused = false,
}) async {
  final ({List<QueuedLog> ready, List<QueuedLog> cancelled, DateTime? next})
  batch = readyLogs(await bridge.pendingLogs(), uid: uid, now: now);
  final List<QueuedLog> done = <QueuedLog>[...batch.cancelled];
  await Future.wait(<Future<void>>[
    for (final QueuedLog log in batch.ready)
      _write(log, writes, rejected, keepRefused: keepRefused).then((bool ok) {
        if (ok) {
          done.add(log);
        }
      }),
  ]);
  if (done.isNotEmpty) {
    await bridge.removeLogs(done);
  }
  return batch.next;
}

// Whether the log can leave the queue.
Future<bool> _write(
  QueuedLog log,
  TrackerWrites writes,
  RejectedWrites rejected, {
  required bool keepRefused,
}) async {
  final SentWrite write = switch (log.op) {
    QueuedLogOp.log => writes.recordActivity(
      log.id,
      ownerID: log.uid,
      viceID: log.viceID,
      quantity: defaultQuantity,
      createdAt: log.createdAt,
    ),
    QueuedLogOp.delete => writes.deleteActivity(log.id),
  };
  final bool creates = log.op == QueuedLogOp.log;
  final String what = creates
      ? 'Not saved: $widgetLogWhat'
      : 'Not undone: $widgetLogWhat';
  try {
    await rejected.settle(write, what);
    return true;
  } on FirebaseException catch (e, stack) {
    // Refused (a habit deleted since the tap, say): writing it again would
    // be refused again, so it goes to the banner and leaves the queue.
    reportError(e, stack, context: 'while writing $widgetLogWhat');
    if (keepRefused) {
      return false;
    }
    rejected.reporter(
      what,
      creates: creates ? log.id : null,
      changes: creates ? null : log.id,
    )(e);
    return true;
  }
}

/// Writes the widgets' queued logs while someone is signed in with the journal
/// key loaded: at once, on every resume, when a held-back log comes due, and
/// when native asks (a log queued while the app runs, or a background
/// refresh). Nothing polls: native hears each enqueue from the extension.
final widgetLogFlushProvider = Provider<void>((ref) {
  if (!widgetsSupported) {
    return;
  }
  final String? uid = ref.watch(
    userProvider.select((AsyncValue<User?> u) => u.value?.uid),
  );
  if (uid == null) {
    return;
  }
  // Until the key loads (or while it is missing or locked) TrackerWrites has
  // no sealer and would store the log without its sealed field. The queue
  // keeps it, and the sealer arriving rebuilds this provider.
  if (ref.watch(e2eeEnabledProvider) && ref.watch(sealerProvider) == null) {
    return;
  }
  final WidgetBridge bridge = ref.watch(widgetBridgeProvider);
  final TrackerWrites writes = ref.watch(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);

  bool disposed = false;
  Future<void>? inFlight;
  Timer? due;
  late final Future<void> Function() flush;
  Future<void> run() async {
    try {
      final DateTime? next = await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: rejected,
        uid: uid,
        now: DateTime.now(),
      );
      due?.cancel();
      if (next != null && !disposed) {
        due = Timer(next.difference(DateTime.now()), flush);
      }
    } on Object catch (e, stack) {
      reportError(e, stack, context: 'while flushing $widgetLogWhat');
    }
  }

  // A request during a flush waits for that one rather than starting another.
  flush = () {
    if (disposed) {
      return Future<void>.value();
    }
    return inFlight ??= run().whenComplete(() => inFlight = null);
  };

  final AppLifecycleListener lifecycle = AppLifecycleListener(onResume: flush);
  bridge.onFlushRequest(flush);
  ref.onDispose(() {
    disposed = true;
    due?.cancel();
    bridge.onFlushRequest(null);
    lifecycle.dispose();
  });
  unawaited(flush());
});
