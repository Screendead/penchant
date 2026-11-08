import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/queued_log.dart';
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
Future<DateTime?> flushQueuedLogs({
  required WidgetBridge bridge,
  required TrackerWrites writes,
  required RejectedWrites rejected,
  required String uid,
  required DateTime now,
}) async {
  final ({List<QueuedLog> ready, List<QueuedLog> cancelled, DateTime? next})
  batch = readyLogs(await bridge.pendingLogs(), uid: uid, now: now);
  final List<QueuedLog> done = <QueuedLog>[...batch.cancelled];
  await Future.wait(<Future<void>>[
    for (final QueuedLog log in batch.ready)
      _write(log, writes, rejected).then((_) => done.add(log)),
  ]);
  if (done.isNotEmpty) {
    await bridge.removeLogs(done);
  }
  return batch.next;
}

Future<void> _write(
  QueuedLog log,
  TrackerWrites writes,
  RejectedWrites rejected,
) async {
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
  try {
    await rejected.settle(
      write,
      log.op == QueuedLogOp.log
          ? 'Not saved: $widgetLogWhat'
          : 'Not undone: $widgetLogWhat',
    );
  } on FirebaseException catch (e, stack) {
    // Refused (a habit deleted since the tap, say): writing it again would
    // be refused again.
    reportError(e, stack, context: 'while writing $widgetLogWhat');
  }
}

// How often a running app looks for logs while it stays open, as the Mac app
// does beside Notification Centre.
const Duration queuedLogPoll = Duration(minutes: 1);

/// Writes the widgets' queued logs while someone is signed in: at once, on
/// every resume, when a held-back log comes due, and every [queuedLogPoll].
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
  final WidgetBridge bridge = ref.watch(widgetBridgeProvider);
  final TrackerWrites writes = ref.watch(trackerWritesProvider);
  final RejectedWrites rejected = ref.read(rejectedWritesProvider.notifier);

  bool disposed = false;
  bool running = false;
  Timer? due;
  Future<void> flush() async {
    if (disposed || running) {
      return;
    }
    running = true;
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
    } finally {
      running = false;
    }
  }

  final AppLifecycleListener lifecycle = AppLifecycleListener(onResume: flush);
  final Timer poll = Timer.periodic(queuedLogPoll, (_) => flush());
  ref.onDispose(() {
    disposed = true;
    due?.cancel();
    poll.cancel();
    lifecycle.dispose();
  });
  unawaited(flush());
});
