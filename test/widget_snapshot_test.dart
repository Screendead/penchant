import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/widget_snapshot.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';

import 'fakes.dart';

Vice _vice(
  String id,
  int order, {
  bool archived = false,
  bool locked = false,
  Unit unit = Unit.drink,
}) => Vice(
  id: id,
  name: id,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(order * 1000),
  archived: archived,
  locked: locked,
);

class _FakeBridge implements WidgetBridge {
  final List<String> calls = <String>[];

  @override
  Future<void> save(String snapshot) async => calls.add('save');

  @override
  Future<void> clear() async => calls.add('clear');

  @override
  Future<List<QueuedLog>> pendingLogs() async => const <QueuedLog>[];

  @override
  Future<void> removeLogs(List<QueuedLog> done) async => calls.add('remove');

  @override
  void onFlushRequest(Future<void> Function()? flush) {}

  @override
  Future<void> backgroundDone(BackgroundFlushOutcome outcome) async {}
}

class _FixedToday extends Today {
  _FixedToday(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final DateTime today = DateTime(2026, 11, 8);

  group('widgetSnapshot', () {
    test('carries the last 7 days, oldest first, per unarchived habit', () {
      final Map<String, Object?> snapshot = widgetSnapshot(
        uid: 'u1',
        vices: <Vice>[_vice('Tea', 1), _vice('Coffee', 0)],
        activities: <ViceActivity>[
          fakeActivity('Coffee', 2, DateTime(2026, 11, 8, 9)),
          fakeActivity('Coffee', 1, DateTime(2026, 11, 8, 14)),
          fakeActivity('Coffee', 1, DateTime(2026, 11, 2, 0, 1)),
          // Outside the week: counts toward the top habits only.
          fakeActivity('Tea', 1, DateTime(2026, 11, 1, 23, 59)),
          fakeActivity('Tea', 1, DateTime(2026, 11, 5), amount: 0.5),
        ],
        today: DateTime(2026, 11, 8, 21, 10),
      );

      expect(snapshot['days'], <String>[
        '2026-11-02',
        '2026-11-03',
        '2026-11-04',
        '2026-11-05',
        '2026-11-06',
        '2026-11-07',
        '2026-11-08',
      ]);
      final List<Map<String, Object?>> habits =
          snapshot['habits']! as List<Map<String, Object?>>;
      expect(habits.map((Map<String, Object?> h) => h['name']), <String>[
        'Coffee',
        'Tea',
      ]);
      expect(habits[0]['week'], <num>[1, 0, 0, 0, 0, 0, 3]);
      expect(habits[1]['week'], <num>[0, 0, 0, 0.5, 0, 0, 0]);
      expect(habits[0]['weekEntries'], <int>[1, 0, 0, 0, 0, 0, 2]);
      expect(habits[0]['unitOne'], 'drink');
      expect(habits[0]['unitOther'], 'drinks');
      expect(habits[0]['slot'], 0);
      expect(habits[1]['slot'], 1);
      expect(habits[0]['style'], 'filled');
    });

    test('keeps archived habits\' colour slots but leaves them out', () {
      final Map<String, Object?> snapshot = widgetSnapshot(
        uid: 'u1',
        vices: <Vice>[
          _vice('Sugar', 0, archived: true),
          _vice('Coffee', 1),
          _vice('Locked', 2, locked: true),
        ],
        activities: const <ViceActivity>[],
        today: today,
      );
      final List<Map<String, Object?>> habits =
          snapshot['habits']! as List<Map<String, Object?>>;
      expect(habits, hasLength(1));
      expect(habits.single['name'], 'Coffee');
      expect(habits.single['slot'], 1);
      expect(snapshot['top'], <String>['Coffee']);
    });

    test('ranks the top habits by entries in 30 days, then creation', () {
      final List<Vice> vices = <Vice>[
        for (int i = 0; i < 10; i++) _vice('H$i', i),
      ];
      final Map<String, Object?> snapshot = widgetSnapshot(
        uid: 'u1',
        vices: vices,
        activities: <ViceActivity>[
          for (int n = 0; n < 3; n++)
            fakeActivity('H9', 1, DateTime(2026, 10, 10 + n)),
          fakeActivity('H5', 40, DateTime(2026, 11, 1)),
          fakeActivity('H5', 1, DateTime(2026, 11, 2)),
          // 30 days end today: the 9th of October is the 31st day back.
          for (int n = 0; n < 5; n++)
            fakeActivity('H2', 1, DateTime(2026, 10, 9, 12)),
        ],
        today: today,
      );
      expect(snapshot['top'], <String>[
        'H9',
        'H5',
        'H0',
        'H1',
        'H2',
        'H3',
        'H4',
        'H6',
      ]);
    });
  });

  group('widgetSyncProvider', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('writes once a burst settles, and clears on sign-out', () async {
      final _FakeBridge bridge = _FakeBridge();
      final StreamController<User?> users = StreamController<User?>();
      final StreamController<List<ViceActivity>> activities =
          StreamController<List<ViceActivity>>();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          widgetBridgeProvider.overrideWithValue(bridge),
          todayProvider.overrideWith(() => _FixedToday(today)),
          userProvider.overrideWith((ref) => users.stream),
          viceListForUserProvider.overrideWith(
            (ref, uid) => Stream<List<Vice>>.value(<Vice>[_vice('Coffee', 0)]),
          ),
          viceActivityRecentForUserProvider.overrideWith(
            (ref, key) => activities.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => unawaited(users.close()));
      addTearDown(() => unawaited(activities.close()));
      container.listen(widgetSyncProvider, (_, _) {});

      users.add(FakeUser('u1'));
      await pumpEventQueue();
      activities.add(<ViceActivity>[fakeActivity('Coffee', 1, today)]);
      await pumpEventQueue();
      activities.add(<ViceActivity>[
        fakeActivity('Coffee', 1, today),
        fakeActivity('Coffee', 2, today),
      ]);
      await pumpEventQueue();
      expect(bridge.calls, isEmpty);

      await Future<void>.delayed(
        widgetSnapshotSettle + const Duration(milliseconds: 50),
      );
      expect(bridge.calls, <String>['save']);

      users.add(null);
      await pumpEventQueue();
      expect(bridge.calls, <String>['save', 'clear']);
    });
  });
}
