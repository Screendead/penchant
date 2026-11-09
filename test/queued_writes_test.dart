import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/rejected_writes_banner.dart';
import 'package:tracker/writes/queued_write_journal.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'fake_writes.dart';
import 'fakes.dart';

QueuedWrite _entry(
  String id,
  WriteOp op, {
  String what = 'Not saved: Coffee',
  String uid = ownerID,
  Map<String, Object> fields = const <String, Object>{},
}) => QueuedWrite(
  uid: uid,
  what: what,
  collection: 'activities',
  id: id,
  op: op,
  fields: fields,
);

// A journal file as an earlier launch left it.
Future<MemoryJournalStore> _leftBehind(List<QueuedWrite> entries) async {
  final MemoryJournalStore store = MemoryJournalStore();
  final QueuedWriteJournal earlier = QueuedWriteJournal(store);
  for (final QueuedWrite entry in entries) {
    await earlier.add(entry);
  }
  return store;
}

List<Object?> _stored(MemoryJournalStore store) =>
    store.contents == null ? const [] : jsonDecode(store.contents!) as List;

FirebaseException _denied() => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message: 'permission-denied',
);

void main() {
  group('refusedAmong', () {
    final QueuedWrite create = _entry('a', WriteOp.create);
    final QueuedWrite delete = _entry('a', WriteOp.delete);
    final QueuedWrite setQuantity = _entry(
      'a',
      WriteOp.update,
      fields: {'quantity': 3},
    );
    final DateTime at = DateTime(2026, 11, 6, 8, 15, 30, 123, 456);
    final QueuedWrite setTime = _entry(
      'a',
      WriteOp.update,
      fields: {'createdAt': comparableValue(at)!},
    );

    test('a create the server lacks was refused', () {
      expect(refusedAmong([create], null), [create]);
      expect(refusedAmong([create], {'quantity': 2}), isEmpty);
    });

    test('a delete is refused only if the document is still there', () {
      expect(refusedAmong([delete], null), isEmpty);
      expect(refusedAmong([delete], {'quantity': 2}), [delete]);
    });

    test('a create and its Undo leave nothing to report once both land', () {
      expect(refusedAmong([create, delete], null), isEmpty);
      expect(refusedAmong([create, delete], {'quantity': 2}), [delete]);
    });

    test('a refused create stands for the edits made after it', () {
      expect(refusedAmong([create, setQuantity], null), [create]);
    });

    test('an edit is refused if the server holds another value', () {
      expect(refusedAmong([setQuantity], {'quantity': 2}), [setQuantity]);
      expect(refusedAmong([setQuantity], {'quantity': 3}), isEmpty);
      expect(refusedAmong([setQuantity], null), [setQuantity]);
    });

    test('a time written as a DateTime matches the Timestamp read back', () {
      expect(
        refusedAmong([setTime], {'createdAt': Timestamp.fromDate(at)}),
        isEmpty,
      );
      expect(
        refusedAmong(
          [setTime],
          {'createdAt': Timestamp.fromDate(at.add(const Duration(minutes: 1)))},
        ),
        [setTime],
      );
    });

    test('of two edits to one field, the later is the one refused', () {
      final QueuedWrite again = _entry(
        'a',
        WriteOp.update,
        fields: {'quantity': 4},
      );
      expect(refusedAmong([setQuantity, again], {'quantity': 3}), [again]);
    });

    test('a field written since is left out of the comparison', () {
      expect(
        refusedAmong(
          [setQuantity],
          {'quantity': 4},
          ignoring: const {'quantity'},
        ),
        isEmpty,
      );
      expect(
        refusedAmong(
          [setQuantity],
          {'quantity': 2},
          ignoring: const {'createdAt'},
        ),
        [setQuantity],
      );
    });
  });

  group('QueuedWriteJournal', () {
    test('keeps an entry on the device until it is removed', () async {
      final MemoryJournalStore store = MemoryJournalStore();
      final QueuedWriteJournal journal = QueuedWriteJournal(store);
      final QueuedWrite entry = _entry('a', WriteOp.create);
      await journal.add(entry);
      expect(_stored(store), hasLength(1));
      await journal.remove([entry]);
      expect(_stored(store), isEmpty);
    });

    test(
      'hands out only what earlier launches left, for that user, once',
      () async {
        final MemoryJournalStore store = await _leftBehind([
          _entry('a', WriteOp.create),
          _entry('a', WriteOp.delete),
          _entry('b', WriteOp.create),
          _entry('c', WriteOp.create, uid: 'someone-else'),
        ]);
        final QueuedWriteJournal journal = QueuedWriteJournal(store);
        await journal.add(_entry('d', WriteOp.create));

        final Map<String, List<QueuedWrite>> earlier = await journal
            .claimEarlier(ownerID);
        expect(earlier.keys, ['activities/a', 'activities/b']);
        expect(earlier['activities/a']!.map((QueuedWrite w) => w.op), [
          WriteOp.create,
          WriteOp.delete,
        ]);
        expect(await journal.claimEarlier(ownerID), isEmpty);

        journal.release(earlier['activities/b']!);
        expect((await journal.claimEarlier(ownerID)).keys, ['activities/b']);
      },
    );

    test('entries it cannot parse are skipped', () async {
      final QueuedWriteJournal journal = QueuedWriteJournal(
        MemoryJournalStore('[{"uid": 3}, "x"]'),
      );
      expect(await journal.claimEarlier(ownerID), isEmpty);
    });

    test('a journal that is not JSON reads as empty', () async {
      final QueuedWriteJournal journal = QueuedWriteJournal(
        MemoryJournalStore('not json'),
      );
      expect(await journal.claimEarlier(ownerID), isEmpty);
    });

    test('clear drops every entry', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create),
      ]);
      await QueuedWriteJournal(store).clear();
      expect(_stored(store), isEmpty);
    });
  });

  group('RejectedWrites', () {
    late FakeTrackerWrites writes;

    setUp(() {
      writes = FakeTrackerWrites();
    });

    // A launch: a new container over the journal [store].
    Future<ProviderContainer> launch(
      MemoryJournalStore store, {
      String uid = ownerID,
    }) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(uid))),
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(store),
        ],
      );
      addTearDown(container.dispose);
      container.listen(userProvider, (_, _) {});
      container.listen(rejectedWritesProvider, (_, _) {});
      await container.read(userProvider.future);
      await pumpEventQueue();
      return container;
    }

    List<String> shown(ProviderContainer container) => [
      for (final RejectedWrite item in container.read(rejectedWritesProvider))
        item.what,
    ];

    test(
      'a write is kept in the journal until the server answers it',
      () async {
        final MemoryJournalStore store = MemoryJournalStore();
        final Completer<void> answer = Completer<void>();
        writes.respond = (_) => answer.future;
        final ProviderContainer container = await launch(store);

        unawaited(
          container
              .read(rejectedWritesProvider.notifier)
              .settle(writes.deleteActivity('a'), 'Not deleted: Coffee')
              .then((_) {}, onError: (Object _) {}),
        );
        await pumpEventQueue();
        expect(_stored(store), [
          {
            'uid': ownerID,
            'what': 'Not deleted: Coffee',
            'collection': 'activities',
            'id': 'a',
            'op': 'delete',
            'fields': <String, Object?>{},
          },
        ]);

        answer.complete();
        await pumpEventQueue();
        expect(_stored(store), isEmpty);
      },
    );

    test('a write refused in this launch leaves the journal too', () async {
      final MemoryJournalStore store = MemoryJournalStore();
      writes.respond = (_) => Future<void>.error(_denied());
      final ProviderContainer container = await launch(store);

      await expectLater(
        container
            .read(rejectedWritesProvider.notifier)
            .settle(writes.deleteActivity('a'), 'Not deleted: Coffee'),
        throwsA(isA<FirebaseException>()),
      );
      await pumpEventQueue();
      expect(_stored(store), isEmpty);
    });

    test('names a write an earlier launch queued that the server does not '
        'hold, and forgets the ones it checked', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('refused', WriteOp.create, what: 'Not saved: Coffee, 2 drinks'),
        _entry('taken', WriteOp.create, what: 'Not saved: Sweets, 1 item'),
        _entry('undone', WriteOp.create, what: 'Not saved: Sweets, 3 items'),
        _entry('undone', WriteOp.delete, what: 'Not deleted: Sweets, 3 items'),
      ]);
      writes.server['activities/taken'] = {'quantity': 1};
      final ProviderContainer container = await launch(store);

      expect(shown(container), ['Not saved: Coffee, 2 drinks']);
      final RejectedWrite rejected = container
          .read(rejectedWritesProvider)
          .single;
      expect(rejected.error, isNull);
      expect(rejected.reason, 'The server refused this change.');
      expect(_stored(store), isEmpty);
    });

    test('checks nothing until the queue has drained', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create),
      ]);
      final Completer<void> drained = Completer<void>();
      writes.pendingWrites = drained.future;
      final ProviderContainer container = await launch(store);

      expect(writes.checked, isEmpty);
      drained.complete();
      await pumpEventQueue();
      expect(writes.checked, ['activities/a']);
      expect(shown(container), ['Not saved: Coffee']);
    });

    test('keeps the writes for the next launch when the server cannot '
        'answer', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create),
      ]);
      writes.serverError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final ProviderContainer container = await launch(store);

      expect(shown(container), isEmpty);
      expect(_stored(store), hasLength(1));
    });

    test('leaves another user\'s writes alone', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create, uid: 'someone-else'),
      ]);
      final ProviderContainer container = await launch(store);

      expect(writes.checked, isEmpty);
      expect(shown(container), isEmpty);
      expect(_stored(store), hasLength(1));
    });

    test('drops an earlier write to a document this launch has since '
        'deleted, whose own answer says what became of it', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create),
      ]);
      final Completer<void> drained = Completer<void>();
      writes.pendingWrites = drained.future;
      final ProviderContainer container = await launch(store);

      await container
          .read(rejectedWritesProvider.notifier)
          .settle(writes.deleteActivity('a'), 'Not deleted: Coffee');
      drained.complete();
      await pumpEventQueue();

      expect(writes.checked, isEmpty);
      expect(shown(container), isEmpty);
      expect(_stored(store), isEmpty);
    });

    test('still names an earlier edit refused on a field this launch did '
        'not write to the same document', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry(
          'a',
          WriteOp.update,
          what: 'Change not saved: Coffee, 3 drinks',
          fields: {'quantity': 3},
        ),
      ]);
      final DateTime at = DateTime(2026, 11, 6, 9);
      writes.server['activities/a'] = {
        'quantity': 2,
        'createdAt': Timestamp.fromDate(at),
      };
      final Completer<void> drained = Completer<void>();
      writes.pendingWrites = drained.future;
      final ProviderContainer container = await launch(store);

      await container
          .read(rejectedWritesProvider.notifier)
          .settle(
            writes.updateActivity('a', createdAt: at),
            'Change not saved: Coffee, 2 drinks',
          );
      drained.complete();
      await pumpEventQueue();

      expect(shown(container), ['Change not saved: Coffee, 3 drinks']);
      expect(_stored(store), isEmpty);
    });

    test('does not call an earlier edit refused for a field this launch '
        'wrote since', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.update, fields: {'quantity': 3}),
      ]);
      writes.server['activities/a'] = {'quantity': 4};
      final Completer<void> drained = Completer<void>();
      writes.pendingWrites = drained.future;
      final ProviderContainer container = await launch(store);

      await container
          .read(rejectedWritesProvider.notifier)
          .settle(
            writes.updateActivity('a', quantity: 4),
            'Change not saved: Coffee',
          );
      drained.complete();
      await pumpEventQueue();

      expect(writes.checked, ['activities/a']);
      expect(shown(container), isEmpty);
      expect(_stored(store), isEmpty);
    });

    test('names an earlier refused create that this launch edited, in place '
        'of the edit', () async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create, what: 'Not saved: Coffee, 2 drinks'),
      ]);
      final Completer<void> drained = Completer<void>();
      writes.pendingWrites = drained.future;
      final ProviderContainer container = await launch(store);
      final RejectedWrites rejected = container.read(
        rejectedWritesProvider.notifier,
      );

      await rejected.settle(
        writes.updateActivity('a', quantity: 3),
        'Change not saved: Coffee, 3 drinks',
      );
      drained.complete();
      await pumpEventQueue();
      expect(shown(container), ['Not saved: Coffee, 2 drinks']);

      // The edit's own refusal, arriving after the check, is not shown.
      rejected.reporter('Change not saved: Coffee, 3 drinks', changes: 'a')(
        _denied(),
      );
      expect(shown(container), ['Not saved: Coffee, 2 drinks']);
    });

    testWidgets('the banner names a refused write from an earlier launch', (
      WidgetTester tester,
    ) async {
      final MemoryJournalStore store = await _leftBehind([
        _entry('a', WriteOp.create, what: 'Not saved: Coffee, 2 drinks'),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProvider.overrideWith(
              (ref) => Stream<User?>.value(FakeUser(ownerID)),
            ),
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(store),
          ],
          child: const MaterialApp(
            builder: rejectedWritesBuilder,
            home: Scaffold(body: Text('Today')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder banner = find.byType(RejectedWritesBanner);
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Not saved: Coffee, 2 drinks'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.text('The server refused this change.'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(RejectedWritesBanner.dismissLabel));
      await tester.pumpAndSettle();
      expect(find.text('Not saved: Coffee, 2 drinks'), findsNothing);
    });
  });
}
