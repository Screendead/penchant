import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/queued_log.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widget_bridge/entry_prompt.dart';
import 'package:tracker/widget_bridge/log_queue.dart';
import 'package:tracker/widget_bridge/widget_bridge.dart';

import 'fake_sealer.dart';
import 'fake_widget_bridge.dart';
import 'fake_writes.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<WidgetLogFlusher?> flusher(
    FakeWidgetBridge bridge,
    FakeTrackerWrites writes, {
    bool keyLoaded = true,
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser('u1'))),
        memoryJournal(),
        widgetBridgeProvider.overrideWithValue(bridge),
        trackerWritesProvider.overrideWithValue(writes),
        sealerProvider.overrideWith((ref) => keyLoaded ? FakeSealer() : null),
      ],
    );
    addTearDown(container.dispose);
    container.listen(widgetLogFlushProvider, (_, _) {});
    await container.read(userProvider.future);
    await pumpEventQueue();
    return container.read(widgetLogFlushProvider);
  }

  List<String> written(FakeTrackerWrites writes) => <String>[
    for (final Write w in writes.writes) '${w.op}:${w.id}',
  ];

  test('readyLogs takes a log named to write now inside its hold', () {
    final DateTime now = DateTime(2026, 11, 11, 9);
    final List<QueuedLog> logs = <QueuedLog>[
      queuedLog('a', now),
      queuedLog('b', now),
    ];
    final ready = readyLogs(logs, uid: 'u1', now: now, writeNow: {'a'});
    expect(ready.ready.map((QueuedLog l) => l.id), <String>['a']);
    expect(ready.next, now.add(queuedLogHold));
  });

  test('a log inside its Undo hold is written at once, before the ask, and '
      'no later flush creates it again', () async {
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final FakeWidgetBridge bridge = FakeWidgetBridge(<QueuedLog>[
      queuedLog('a', DateTime.now().subtract(const Duration(seconds: 1))),
    ]);
    final WidgetLogFlusher? flush = await flusher(bridge, writes);
    expect(written(writes), isEmpty, reason: 'held back by the Undo hold');

    final EntryPromptState state = await prepareEntryPrompt(
      bridge: bridge,
      flusher: flush,
      uid: 'u1',
      activityID: 'a',
    );

    expect(state, EntryPromptState.ready);
    expect(written(writes), <String>['recordActivity:a']);
    expect(bridge.queue, isEmpty);

    await flush!.flush();
    expect(written(writes), <String>['recordActivity:a']);
  });

  test('waits for a flush already running before writing the log', () async {
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final FakeWidgetBridge bridge = FakeWidgetBridge(<QueuedLog>[]);
    final WidgetLogFlusher? flush = await flusher(bridge, writes);
    bridge.queue = <QueuedLog>[
      queuedLog('a', DateTime.now().subtract(const Duration(minutes: 1))),
    ];
    final Future<void> running = flush!.flush();

    final EntryPromptState state = await prepareEntryPrompt(
      bridge: bridge,
      flusher: flush,
      uid: 'u1',
      activityID: 'a',
    );
    await running;

    expect(state, EntryPromptState.ready);
    expect(written(writes), <String>['recordActivity:a']);
  });

  test('an entry undone since (its delete queued) writes nothing', () async {
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final DateTime tapped = DateTime.now().subtract(const Duration(seconds: 2));
    final FakeWidgetBridge bridge = FakeWidgetBridge(<QueuedLog>[]);
    final WidgetLogFlusher? flush = await flusher(bridge, writes);
    bridge.queue = <QueuedLog>[
      queuedLog('a', tapped),
      queuedLog('a', tapped, op: QueuedLogOp.delete),
    ];

    final EntryPromptState state = await prepareEntryPrompt(
      bridge: bridge,
      flusher: flush,
      uid: 'u1',
      activityID: 'a',
    );

    expect(state, EntryPromptState.undone);
    expect(writes.writes, isEmpty);
  });

  test('an entry no longer queued was written: ask, writing nothing', () async {
    final FakeTrackerWrites writes = FakeTrackerWrites();
    final FakeWidgetBridge bridge = FakeWidgetBridge(<QueuedLog>[]);
    final WidgetLogFlusher? flush = await flusher(bridge, writes);

    expect(
      await prepareEntryPrompt(
        bridge: bridge,
        flusher: flush,
        uid: 'u1',
        activityID: 'a',
      ),
      EntryPromptState.ready,
    );
    expect(writes.writes, isEmpty);
  });

  test(
    'without the journal key the log stays queued and nothing is asked',
    () async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final FakeWidgetBridge bridge = FakeWidgetBridge(<QueuedLog>[
        queuedLog('a', DateTime.now().subtract(const Duration(seconds: 1))),
      ]);
      final WidgetLogFlusher? flush = await flusher(
        bridge,
        writes,
        keyLoaded: false,
      );
      expect(flush, isNull);

      expect(
        await prepareEntryPrompt(
          bridge: bridge,
          flusher: flush,
          uid: 'u1',
          activityID: 'a',
        ),
        EntryPromptState.unsaved,
      );
      expect(writes.writes, isEmpty);
      expect(bridge.queue.map((QueuedLog l) => l.id), <String>['a']);
    },
  );

  test('the listener takes the entry a launch came with', () async {
    final _FakeChannel channel = _FakeChannel(<EntryPrompt>[
      (activityID: 'a', viceID: 'coffee'),
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: [entryPromptChannelProvider.overrideWithValue(channel)],
    );
    addTearDown(container.dispose);
    container.listen(entryPromptListenerProvider, (_, _) {});
    await pumpEventQueue();
    expect(container.read(pendingEntryPromptProvider), (
      activityID: 'a',
      viceID: 'coffee',
    ));
    expect(
      container.read(entryPromptReadyProvider),
      isNull,
      reason: 'no journal key yet',
    );

    channel.queue.add((activityID: 'b', viceID: 'tea'));
    channel.changed!();
    await pumpEventQueue();
    expect(container.read(pendingEntryPromptProvider)?.activityID, 'b');
  });
}

class _FakeChannel implements EntryPromptChannel {
  _FakeChannel(this.queue);

  final List<EntryPrompt> queue;
  void Function()? changed;

  @override
  Future<EntryPrompt?> take() async => queue.isEmpty ? null : queue.removeAt(0);

  @override
  void onChanged(void Function()? changed) => this.changed = changed;
}
