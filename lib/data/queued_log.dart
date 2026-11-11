import 'dart:convert';

// A log made outside the app (a widget, a control, Siri or Shortcuts) that
// the app has yet to write. The shape is QueuedLog's in
// ios/PenchantWidgets/LogQueue.swift; a change here is a change there.
enum QueuedLogOp { log, delete }

class QueuedLog {
  const QueuedLog({
    required this.op,
    required this.id,
    required this.uid,
    required this.viceID,
    required this.createdAtMs,
  });

  final QueuedLogOp op;
  final String id;
  final String uid;
  final String viceID;
  // The tap, not the flush.
  final double createdAtMs;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs.round());

  // Swift's synthesized Codable needs every key back, with the same values,
  // for LogQueue.remove to match the entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'op': op.name,
    'id': id,
    'uid': uid,
    'viceID': viceID,
    'createdAt': createdAtMs,
  };

  static QueuedLog? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final QueuedLogOp? op = switch (json['op']) {
      'log' => QueuedLogOp.log,
      'delete' => QueuedLogOp.delete,
      _ => null,
    };
    final Object? id = json['id'];
    final Object? uid = json['uid'];
    final Object? viceID = json['viceID'];
    final Object? createdAt = json['createdAt'];
    if (op == null ||
        id is! String ||
        id.isEmpty ||
        uid is! String ||
        viceID is! String ||
        viceID.isEmpty ||
        createdAt is! num) {
      return null;
    }
    return QueuedLog(
      op: op,
      id: id,
      uid: uid,
      viceID: viceID,
      createdAtMs: createdAt.toDouble(),
    );
  }
}

/// The queue's JSON, skipping any entry this version cannot read.
List<QueuedLog> decodeQueuedLogs(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const <QueuedLog>[];
  }
  if (decoded is! List<Object?>) {
    return const <QueuedLog>[];
  }
  return <QueuedLog>[
    for (final Object? entry in decoded) ?QueuedLog.fromJson(entry),
  ];
}

// The widget offers Undo for 5 seconds (r10-widget-undo B, LastLog.undoWindow
// in LogQueue.swift); a log is written only after that and a margin, so an
// Undo inside the window never has to chase a written entry.
const Duration queuedLogHold = Duration(seconds: 7);

/// [uid]'s logs that are old enough to write at [now], in queue order, and
/// when the next one held back will be. A log and its own delete are both
/// returned as `cancelled`, even while the log is in its hold: the queue drops
/// them, nothing is written. A log whose id is in [writeNow] is ready inside
/// its hold: its entry was opened to say what was going on, which needs it
/// written first.
({List<QueuedLog> ready, List<QueuedLog> cancelled, DateTime? next}) readyLogs(
  List<QueuedLog> logs, {
  required String uid,
  required DateTime now,
  Set<String> writeNow = const <String>{},
}) {
  final List<QueuedLog> mine = <QueuedLog>[
    for (final QueuedLog log in logs)
      if (log.uid == uid) log,
  ];
  final Set<String> deleted = <String>{
    for (final QueuedLog log in mine)
      if (log.op == QueuedLogOp.delete) log.id,
  };
  final Set<String> logged = <String>{
    for (final QueuedLog log in mine)
      if (log.op == QueuedLogOp.log) log.id,
  };
  final Set<String> both = deleted.intersection(logged);
  final List<QueuedLog> ready = <QueuedLog>[];
  final List<QueuedLog> cancelled = <QueuedLog>[];
  DateTime? next;
  for (final QueuedLog log in mine) {
    if (both.contains(log.id)) {
      cancelled.add(log);
      continue;
    }
    final DateTime due = log.createdAt.add(queuedLogHold);
    if (log.op == QueuedLogOp.delete ||
        !due.isAfter(now) ||
        writeNow.contains(log.id)) {
      ready.add(log);
    } else if (next == null || due.isBefore(next)) {
      next = due;
    }
  }
  return (ready: ready, cancelled: cancelled, next: next);
}
