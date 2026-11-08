import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/log_queue.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/writes/rejected_writes.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class _QueueBridge implements WidgetBridge {
  _QueueBridge(this.queue);

  List<QueuedLog> queue;
  final List<List<String>> removed = <List<String>>[];

  @override
  Future<void> save(String snapshot) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<QueuedLog>> pendingLogs() async => decodeQueuedLogs(
    jsonEncode(<Object?>[for (final l in queue) l.toJson()]),
  );

  @override
  Future<void> removeLogs(List<QueuedLog> done) async {
    removed.add(<String>[
      for (final QueuedLog l in done) '${l.op.name}:${l.id}',
    ]);
    queue = <QueuedLog>[
      for (final QueuedLog l in queue)
        if (!done.any((QueuedLog d) => d.id == l.id && d.op == l.op)) l,
    ];
  }
}

QueuedLog _log(
  String id,
  DateTime at, {
  QueuedLogOp op = QueuedLogOp.log,
  String uid = 'u1',
}) => QueuedLog(
  op: op,
  id: id,
  uid: uid,
  viceID: 'coffee',
  createdAtMs: at.millisecondsSinceEpoch.toDouble(),
);

void main() {
  final DateTime now = DateTime(2026, 11, 8, 13);

  group('decodeQueuedLogs', () {
    test('reads what LogQueue.swift writes and skips what it cannot', () {
      final List<QueuedLog> logs = decodeQueuedLogs(
        jsonEncode(<Object?>[
          <String, Object?>{
            'op': 'log',
            'id': 'a',
            'uid': 'u1',
            'viceID': 'coffee',
            'createdAt': 1794142800000.0,
          },
          <String, Object?>{'op': 'log', 'id': 'b'},
          <String, Object?>{
            'op': 'rename',
            'id': 'c',
            'uid': 'u1',
            'viceID': 'coffee',
            'createdAt': 1,
          },
          'junk',
        ]),
      );
      expect(logs.map((QueuedLog l) => l.id), <String>['a']);
      expect(logs.single.createdAt.millisecondsSinceEpoch, 1794142800000);
      expect(logs.single.toJson()['createdAt'], 1794142800000.0);
      expect(decodeQueuedLogs('not json'), isEmpty);
    });
  });

  group('readyLogs', () {
    test('holds back a log inside the Undo window, and another user\'s', () {
      final result = readyLogs(
        <QueuedLog>[
          _log('old', now.subtract(const Duration(minutes: 5))),
          _log('young', now.subtract(const Duration(seconds: 2))),
          _log('other', now.subtract(const Duration(hours: 1)), uid: 'u2'),
        ],
        uid: 'u1',
        now: now,
      );
      expect(result.ready.map((QueuedLog l) => l.id), <String>['old']);
      expect(
        result.next,
        now.subtract(const Duration(seconds: 2)).add(queuedLogHold),
      );
    });

    test('a log and its own delete cancel out', () {
      final DateTime at = now.subtract(const Duration(minutes: 1));
      final result = readyLogs(
        <QueuedLog>[
          _log('a', at),
          _log('a', at, op: QueuedLogOp.delete),
          _log('b', at, op: QueuedLogOp.delete),
        ],
        uid: 'u1',
        now: now,
      );
      expect(
        result.ready.map((QueuedLog l) => '${l.op.name}:${l.id}'),
        <String>['delete:b'],
      );
      expect(result.cancelled.length, 2);
    });
  });

  group('flushQueuedLogs', () {
    Future<ProviderContainer> signedIn() async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
          memoryJournal(),
        ],
      );
      addTearDown(container.dispose);
      container.listen(userProvider, (_, _) {});
      await container.read(userProvider.future);
      return container;
    }

    test('writes each ready log with its own id and tap time, then '
        'removes it', () async {
      final ProviderContainer container = await signedIn();
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final DateTime tapped = now.subtract(const Duration(hours: 3));
      final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
        _log('a', tapped),
        _log('young', now.subtract(const Duration(seconds: 1))),
        _log('gone', tapped, op: QueuedLogOp.delete),
      ]);

      final DateTime? next = await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: container.read(rejectedWritesProvider.notifier),
        uid: 'u1',
        now: now,
      );

      expect(writes.writes.map((Write w) => '${w.op}:${w.id}'), <String>[
        'recordActivity:a',
        'deleteActivity:gone',
      ]);
      expect(writes.writes.first.fields, <String, Object?>{
        'ownerID': 'u1',
        'viceID': 'coffee',
        'quantity': 1,
        'createdAt': tapped,
      });
      expect(bridge.queue.map((QueuedLog l) => l.id), <String>['young']);
      expect(next, isNotNull);
    });

    // testWidgets, which demangles the stack reportError prints.
    testWidgets('a refused write leaves the queue too', (tester) async {
      final ProviderContainer container = await signedIn();
      final FakeTrackerWrites writes = FakeTrackerWrites()
        ..respond = (Write w) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );
      final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
        _log('a', now.subtract(const Duration(hours: 3))),
      ]);

      await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: container.read(rejectedWritesProvider.notifier),
        uid: 'u1',
        now: now,
      );
      expect(bridge.queue, isEmpty);
    });
  });
}
