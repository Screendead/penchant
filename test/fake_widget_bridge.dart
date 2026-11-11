import 'package:tracker/data/queued_log.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';

// The App Group's log queue in memory, for WidgetBridge's queue calls.
class FakeWidgetBridge implements WidgetBridge {
  FakeWidgetBridge([List<QueuedLog>? queue]) : queue = queue ?? <QueuedLog>[];

  List<QueuedLog> queue;

  @override
  Future<void> save(String snapshot) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<QueuedLog>> pendingLogs() async => List<QueuedLog>.of(queue);

  @override
  Future<void> removeLogs(List<QueuedLog> done) async {
    queue = <QueuedLog>[
      for (final QueuedLog l in queue)
        if (!done.any((QueuedLog d) => d.id == l.id && d.op == l.op)) l,
    ];
  }

  @override
  void onFlushRequest(Future<void> Function()? flush) {}

  @override
  Future<void> backgroundDone(BackgroundFlushOutcome outcome) async {}
}

QueuedLog queuedLog(
  String id,
  DateTime at, {
  QueuedLogOp op = QueuedLogOp.log,
  String uid = 'u1',
  String viceID = 'coffee',
}) => QueuedLog(
  op: op,
  id: id,
  uid: uid,
  viceID: viceID,
  createdAtMs: at.millisecondsSinceEpoch.toDouble(),
);
