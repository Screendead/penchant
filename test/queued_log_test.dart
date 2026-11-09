import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/e2ee_enabled.dart';
import 'package:tracker/crypto/key_service.dart';
import 'package:tracker/crypto/key_wiring.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/background_flush.dart';
import 'package:tracker/widget_bridge/log_queue.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

import 'fake_sealer.dart';
import 'fake_writes.dart';
import 'fakes.dart';

class _KeySlot extends Notifier<FieldSealer?> {
  @override
  FieldSealer? build() => null;

  void load() => state = FakeSealer();
}

final _keySlot = NotifierProvider<_KeySlot, FieldSealer?>(_KeySlot.new);

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

  Future<void> Function()? flushRequest;

  @override
  void onFlushRequest(Future<void> Function()? flush) => flushRequest = flush;

  @override
  Future<void> backgroundDone(BackgroundFlushOutcome outcome) async {}
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

      final DateTime? next = (await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: container.read(rejectedWritesProvider.notifier),
        uid: 'u1',
        now: now,
      )).next;

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

    test('without the journal key writes deletes only, and keeps the logs '
        'queued', () async {
      final ProviderContainer container = await signedIn();
      final FakeTrackerWrites writes = FakeTrackerWrites()..canCreate = false;
      final DateTime tapped = now.subtract(const Duration(hours: 3));
      final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
        _log('a', tapped),
        _log('gone', tapped, op: QueuedLogOp.delete),
      ]);

      final FlushLeft left = await flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: container.read(rejectedWritesProvider.notifier),
        uid: 'u1',
        now: now,
      );

      expect(writes.writes.map((Write w) => '${w.op}:${w.id}'), <String>[
        'deleteActivity:gone',
      ]);
      expect(bridge.queue.map((QueuedLog l) => l.id), <String>['a']);
      expect(left.unacknowledged, isTrue);
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
      expect(
        container.read(rejectedWritesProvider).map((r) => r.what),
        <String>['Not saved: $widgetLogWhat'],
      );
    });
  });

  test('widgetLogFlushProvider writes nothing until the journal key loads, '
      'then flushes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
      _log('a', DateTime.now().subtract(const Duration(hours: 3))),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
        memoryJournal(),
        widgetBridgeProvider.overrideWithValue(bridge),
        trackerWritesProvider.overrideWithValue(writes),
        sealerProvider.overrideWith((ref) => ref.watch(_keySlot)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(widgetLogFlushProvider, (_, _) {});
    await container.read(userProvider.future);
    await pumpEventQueue();
    expect(writes.writes, isEmpty);
    expect(bridge.removed, isEmpty);
    expect(bridge.queue.map((QueuedLog l) => l.id), <String>['a']);

    container.read(_keySlot.notifier).load();
    await pumpEventQueue();
    expect(writes.writes.map((Write w) => '${w.op}:${w.id}'), <String>[
      'recordActivity:a',
    ]);
    expect(bridge.queue, isEmpty);
  });

  test(
    'a flush native asks for writes logs queued while the app runs',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final _QueueBridge bridge = _QueueBridge(<QueuedLog>[]);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
          memoryJournal(),
          widgetBridgeProvider.overrideWithValue(bridge),
          trackerWritesProvider.overrideWithValue(writes),
          sealerProvider.overrideWith((ref) => FakeSealer()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(widgetLogFlushProvider, (_, _) {});
      await container.read(userProvider.future);
      await pumpEventQueue();
      expect(bridge.flushRequest, isNotNull);

      bridge.queue = <QueuedLog>[
        _log('a', DateTime.now().subtract(const Duration(minutes: 1))),
      ];
      await bridge.flushRequest!();
      expect(writes.writes.map((Write w) => '${w.op}:${w.id}'), <String>[
        'recordActivity:a',
      ]);
      expect(bridge.queue, isEmpty);

      container.dispose();
      expect(bridge.flushRequest, isNull);
    },
  );

  // testWidgets, which demangles the stack reportError prints.
  testWidgets('flushQueuedLogs in the background leaves a refused log queued '
      'and reports nothing', (tester) async {
    final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
      _log('a', DateTime(2026, 11, 8, 9)),
    ]);
    final FakeTrackerWrites writes = FakeTrackerWrites()
      ..respond = (Write w) => Future<void>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
        memoryJournal(),
      ],
    );
    addTearDown(container.dispose);
    container.listen(userProvider, (_, _) {});
    await container.read(userProvider.future);
    final FlushLeft left = await flushQueuedLogs(
      bridge: bridge,
      writes: writes,
      rejected: container.read(rejectedWritesProvider.notifier),
      uid: 'u1',
      now: DateTime(2026, 11, 8, 10),
      inBackground: true,
    );
    expect(bridge.queue.map((QueuedLog l) => l.id), <String>['a']);
    expect(container.read(rejectedWritesProvider), isEmpty);
    expect(left.refused, isTrue);
  });

  // The process that queued it in the SDK exits soon after, so the queue must
  // keep the log for the next flush; a repeat delete would be refused.
  testWidgets('flushQueuedLogs in the background keeps a log the server has '
      'not acknowledged, and lets a delete go', (tester) async {
    final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
      _log('a', DateTime(2026, 11, 8, 9)),
      _log('b', DateTime(2026, 11, 8, 9), op: QueuedLogOp.delete),
    ]);
    final FakeTrackerWrites writes = FakeTrackerWrites()
      ..respond = (Write w) => Completer<void>().future;
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
        memoryJournal(),
      ],
    );
    addTearDown(container.dispose);
    container.listen(userProvider, (_, _) {});
    await tester.pump();
    FlushLeft? left;
    unawaited(
      flushQueuedLogs(
        bridge: bridge,
        writes: writes,
        rejected: container.read(rejectedWritesProvider.notifier),
        uid: 'u1',
        now: DateTime(2026, 11, 8, 10),
        inBackground: true,
      ).then((FlushLeft l) => left = l),
    );
    await tester.pump(writeTimeout + const Duration(seconds: 1));
    expect(left?.unacknowledged, isTrue);
    expect(left?.refused, isFalse);
    expect(bridge.queue.map((QueuedLog l) => '${l.op.name}:${l.id}'), <String>[
      'log:a',
    ]);
  });

  group('runBackgroundFlush', () {
    Future<(BackgroundFlushOutcome, _QueueBridge, FakeTrackerWrites)> run({
      String? uid = 'u1',
      bool e2ee = true,
      JournalKeyState? key,
      Future<void> Function(Write write)? respond,
      bool canCreate = true,
    }) async {
      final _QueueBridge bridge = _QueueBridge(<QueuedLog>[
        _log('a', DateTime(2026, 11, 8, 9)),
      ]);
      final FakeTrackerWrites writes = FakeTrackerWrites()
        ..respond = respond
        ..canCreate = canCreate;
      final BackgroundFlushOutcome outcome = await runBackgroundFlush(
        initialize: () async {},
        overrides: [
          userProvider.overrideWith(
            (ref) => Stream.value(uid == null ? null : FakeUser(uid)),
          ),
          memoryJournal(),
          widgetBridgeProvider.overrideWithValue(bridge),
          trackerWritesProvider.overrideWithValue(writes),
          e2eeEnabledProvider.overrideWithValue(e2ee),
          journalKeyProvider.overrideWithValue(
            key == null
                ? const AsyncLoading<JournalKeyState>()
                : AsyncData<JournalKeyState>(key),
          ),
        ],
        now: () => DateTime(2026, 11, 8, 10),
        readyWithin: const Duration(milliseconds: 50),
      );
      return (outcome, bridge, writes);
    }

    test('signed out: blocked, the queue untouched', () async {
      final (outcome, bridge, writes) = await run(uid: null);
      expect(outcome, BackgroundFlushOutcome.blocked);
      expect(writes.writes, isEmpty);
      expect(bridge.queue, hasLength(1));
    });

    test('no key on the device yet: retry, nothing written unsealed', () async {
      final (outcome, bridge, writes) = await run(key: const KeyUnknown());
      expect(outcome, BackgroundFlushOutcome.retry);
      expect(writes.writes, isEmpty);
      expect(bridge.queue, hasLength(1));
    });

    test('the key never loads in time: retry, the queue untouched', () async {
      final (outcome, bridge, writes) = await run();
      expect(outcome, BackgroundFlushOutcome.retry);
      expect(writes.writes, isEmpty);
      expect(bridge.queue, hasLength(1));
    });

    // testWidgets, which demangles the stack reportError prints.
    testWidgets('a refused log: blocked, left for the app\'s banner', (
      tester,
    ) async {
      final (outcome, bridge, writes) = await run(
        e2ee: false,
        respond: (Write w) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
      );
      expect(outcome, BackgroundFlushOutcome.blocked);
      expect(writes.writes, hasLength(1));
      expect(bridge.queue, hasLength(1));
    });

    test('a log that cannot be created stays queued: retry', () async {
      final (outcome, bridge, writes) = await run(
        e2ee: false,
        canCreate: false,
      );
      expect(outcome, BackgroundFlushOutcome.retry);
      expect(writes.writes, isEmpty);
      expect(bridge.queue, hasLength(1));
    });
  });
}
