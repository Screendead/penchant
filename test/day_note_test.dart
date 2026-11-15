// The Firestore types are @sealed, and a mock is the only way to build one
// without a Firestore instance.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/crypto/plaintext_migrator.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/writes/queued_write_journal.dart';
import 'package:tracker/writes/tracker_writes.dart';

import 'fake_sealer.dart';
import 'fakes.dart';

class _Firestore extends Mock implements FirebaseFirestore {}

class _Collection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _DocRef extends Mock implements DocumentReference<Map<String, dynamic>> {}

const String _day = '2026-11-15';
const String _id = '${ownerID}_$_day';
final Timestamp _at = Timestamp.fromMillisecondsSinceEpoch(1763200000000);

// Records the set, update and delete of the one note the tests write.
class _Store {
  _Store() {
    when(() => collection.id).thenReturn(dayNotesCollection);
    when(() => collection.doc(_id)).thenReturn(note);
    when(() => note.id).thenReturn(_id);
    when(() => note.parent).thenReturn(collection);
    when(() => note.set(any())).thenAnswer((Invocation call) async {
      set = call.positionalArguments.first as Map<String, Object?>;
    });
    when(() => note.update(any())).thenAnswer((Invocation call) async {
      updated = call.positionalArguments.first as Map<Object, Object?>;
    });
    when(() => note.delete()).thenAnswer((_) async => deleted = true);
    when(() => firestore.collection(dayNotesCollection)).thenReturn(collection);
  }

  final _Firestore firestore = _Firestore();
  final _Collection collection = _Collection();
  final _DocRef note = _DocRef();
  Map<String, Object?>? set;
  Map<Object, Object?>? updated;
  bool deleted = false;
}

class _Source implements MigrationSource {
  final List<String> paged = <String>[];

  @override
  Future<void> settlePendingWrites() async {}

  @override
  Future<List<StoredDocument>> page(
    String collection,
    String uid, {
    String? after,
    required int limit,
  }) async {
    paged.add(collection);
    return const <StoredDocument>[];
  }

  @override
  Future<void> commit(
    String collection,
    Map<String, Map<String, Object>> updates,
  ) async {}
}

void main() {
  late FakeSealer sealer;

  setUp(() => sealer = FakeSealer());

  Future<Map<String, Object?>> openEnvelope(Object? blob) =>
      sealer.open((blob! as Blob).bytes, context: 'dayNotes/$_id');

  group('ids and days', () {
    test('a day is its local calendar date, whatever the time', () {
      expect(dayKey(DateTime(2026, 11, 15, 23, 59)), _day);
      expect(dayKey(DateTime(2026, 1, 2)), '2026-01-02');
    });

    test('a note has one id per user per day', () {
      expect(dayNoteID('uid', _day), 'uid_2026-11-15');
    });
  });

  group('DayNote.fromJson', () {
    test('reads an opened note', () {
      final DayNote note = DayNote.fromJson(
        id: _id,
        json: <String, dynamic>{
          'ownerID': ownerID,
          'day': _day,
          'createdAt': _at,
          sealedField: Blob(Uint8List(40)),
        },
        opened: <String, Object?>{
          'text': 'A long day',
          'triggers': <Object?>['work/meeting', 3],
        },
      );
      expect(note.ownerID, ownerID);
      expect(note.day, _day);
      expect(note.createdAt, _at);
      expect(note.text, 'A long day');
      expect(note.triggers, <String>['work/meeting']);
      expect(note.locked, isFalse);
    });

    test('never throws: a note that will not open is locked and empty', () {
      final DayNote note = DayNote.fromJson(
        id: _id,
        json: <String, dynamic>{
          'ownerID': 7,
          'day': 'yesterday',
          'createdAt': 'soon',
          sealedField: 'not bytes',
        },
      );
      expect(note.locked, isTrue);
      expect(note.ownerID, '');
      expect(note.day, '');
      expect(note.createdAt, Timestamp(0, 0));
      expect(note.text, '');
      expect(note.triggers, isEmpty);
    });

    test('mistyped content reads as absent', () {
      final DayNote note = DayNote.fromJson(
        id: _id,
        json: const <String, dynamic>{},
        opened: <String, Object?>{'text': 12, 'triggers': 'work'},
      );
      expect(note.text, '');
      expect(note.triggers, isEmpty);
      expect(note.locked, isFalse);
    });

    test('opens through the opener, with the document path bound', () async {
      final Uint8List envelope = await sealer.seal(<String, Object?>{
        'text': 'Slept badly',
        'triggers': <String>[],
      }, context: 'dayNotes/$_id');
      final Map<String, dynamic> json = <String, dynamic>{
        'ownerID': ownerID,
        'day': _day,
        sealedField: Blob(envelope),
      };
      final SealedOpener opener = SealedOpener(sealer);
      final DayNote here = DayNote.fromJson(
        id: _id,
        json: json,
        opened: await opener.open(dayNotesCollection, _id, json),
      );
      expect(here.text, 'Slept badly');
      final DayNote moved = DayNote.fromJson(
        id: 'other',
        json: json,
        opened: await opener.open(dayNotesCollection, 'other', json),
      );
      expect(moved.locked, isTrue);
    });
  });

  group('dayNoteError', () {
    test('needs words, trimmed, of at most 2000 units', () {
      expect(dayNoteError('  \n ', const <String>[]), isNotNull);
      expect(dayNoteError(' fine ', const <String>[]), isNull);
      expect(dayNoteError('x' * maxDayNoteLength, const <String>[]), isNull);
      expect(
        dayNoteError('  ${'x' * maxDayNoteLength}  ', const <String>[]),
        isNull,
      );
      expect(
        dayNoteError('x' * (maxDayNoteLength + 1), const <String>[]),
        isNotNull,
      );
    });

    test('bounds the triggers as an entry\'s', () {
      expect(dayNoteError('ok', List<String>.filled(10, 'work')), isNull);
      expect(dayNoteError('ok', List<String>.filled(11, 'work')), isNotNull);
      expect(dayNoteError('ok', <String>['']), isNotNull);
      expect(dayNoteError('ok', <String>['x' * 61]), isNotNull);
    });

    test('refuses text that fits the length but not the envelope', () {
      // Each € is one UTF-16 unit and three UTF-8 bytes: 2000 of them is
      // 6000 bytes, past the envelope's 4094; 1300 is 3900.
      expect(
        dayNoteError('€' * maxDayNoteLength, const <String>[]),
        dayNoteTooLong,
      );
      expect(dayNoteError('€' * 1300, const <String>[]), isNull);
    });
  });

  group('TrackerWrites', () {
    test('a new note is created sealed under its day\'s id', () async {
      final _Store store = _Store();
      final SentWrite write = TrackerWrites(store.firestore, sealer: sealer)
          .setDayNote(
            ownerID: ownerID,
            day: _day,
            text: '  A long day  ',
            triggers: <String>['work/meeting'],
          );
      await write.done;
      expect(write.collection, 'dayNotes');
      expect(write.id, _id);
      expect(write.op, WriteOp.create);
      expect(store.set!.keys.toSet(), <String>{
        'sealed',
        'ownerID',
        'day',
        'createdAt',
      });
      expect(store.set!['ownerID'], ownerID);
      expect(store.set!['day'], _day);
      expect(store.set!['createdAt'], FieldValue.serverTimestamp());
      expect(await openEnvelope(store.set![sealedField]), <String, Object?>{
        'text': 'A long day',
        'triggers': <Object?>['work/meeting'],
      });
    });

    test('replacing a note updates its envelope alone', () async {
      final _Store store = _Store();
      final SentWrite write = TrackerWrites(store.firestore, sealer: sealer)
          .setDayNote(
            ownerID: ownerID,
            day: _day,
            text: 'Better by evening',
            replacing: DayNote(
              id: _id,
              ownerID: ownerID,
              day: _day,
              createdAt: _at,
              text: 'A long day',
            ),
          );
      await write.done;
      expect(write.op, WriteOp.update);
      expect(store.set, isNull);
      expect(store.updated!.keys.toList(), <Object>[sealedField]);
      expect(await openEnvelope(store.updated![sealedField]), <String, Object?>{
        'text': 'Better by evening',
        'triggers': <Object?>[],
      });
    });

    test('nothing is written without the journal key', () {
      final _Store store = _Store();
      final TrackerWrites writes = TrackerWrites(store.firestore);
      expect(writes.canCreate, isFalse);
      expect(
        () => writes.setDayNote(ownerID: ownerID, day: _day, text: 'x'),
        throwsStateError,
      );
      verifyNever(() => store.note.set(any()));
    });

    test('a locked note is never replaced unseen', () {
      final _Store store = _Store();
      expect(
        () => TrackerWrites(store.firestore, sealer: sealer).setDayNote(
          ownerID: ownerID,
          day: _day,
          text: 'x',
          replacing: DayNote(
            id: _id,
            ownerID: ownerID,
            day: _day,
            createdAt: _at,
            locked: true,
          ),
        ),
        throwsStateError,
      );
      verifyNever(() => store.note.update(any()));
    });

    test('a note deletes by its day\'s id', () async {
      final _Store store = _Store();
      final SentWrite write = TrackerWrites(
        store.firestore,
        sealer: sealer,
      ).deleteDayNote(ownerID: ownerID, day: _day);
      await write.done;
      expect(store.deleted, isTrue);
      expect(write.op, WriteOp.delete);
      expect(write.id, _id);
    });

    test('a note too long for the envelope fails as a refused save', () async {
      final _Store store = _Store();
      final SentWrite write = TrackerWrites(
        store.firestore,
        sealer: sealer,
      ).setDayNote(ownerID: ownerID, day: _day, text: '"' * 2100);
      await expectLater(write.done, throwsA(isA<FirebaseException>()));
      expect(store.set, isNull);
    });

    test('the write journal keeps a day note like any write', () {
      final QueuedWrite queued = QueuedWrite.fromJson(
        QueuedWrite(
          uid: ownerID,
          collection: dayNotesCollection,
          id: _id,
          op: WriteOp.create,
          what: 'your note on 15 November',
        ).toJson(),
      )!;
      expect(queued.document, 'dayNotes/$_id');
      expect(refusedAmong(<QueuedWrite>[queued], null), <QueuedWrite>[queued]);
      expect(
        refusedAmong(
          <QueuedWrite>[queued],
          <String, Object?>{'ownerID': ownerID, 'day': _day},
        ),
        isEmpty,
      );
    });
  });

  group('dayNoteProvider', () {
    test('is loading while signed out, then follows the signed-in user\'s '
        'note for that day', () async {
      final StreamController<User?> users = StreamController<User?>();
      final List<({String uid, String day})> asked =
          <({String uid, String day})>[];
      final DayNote note = DayNote(
        id: _id,
        ownerID: ownerID,
        day: _day,
        createdAt: _at,
        text: 'A long day',
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => users.stream),
          dayNoteForUserProvider.overrideWith((ref, key) {
            asked.add(key);
            return Stream<DayNote?>.value(key.uid == ownerID ? note : null);
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(users.close);
      final ProviderSubscription<AsyncValue<DayNote?>> sub = container.listen(
        dayNoteProvider(DateTime(2026, 11, 15, 21, 30)),
        (_, _) {},
      );
      expect(sub.read(), isA<AsyncLoading<DayNote?>>());

      users.add(FakeUser(ownerID));
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(asked, <({String uid, String day})>[(uid: ownerID, day: _day)]);
      expect(sub.read().value, note);

      users.add(null);
      for (int i = 0; i < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(sub.read(), isA<AsyncLoading<DayNote?>>());
      expect(sub.read().hasValue, isFalse);
    });
  });

  group('export', () {
    AccountData data({List<StoredDocument> notes = const <StoredDocument>[]}) =>
        AccountData(
          vices: const <StoredDocument>[],
          activities: const <StoredDocument>[],
          dayNotes: notes,
        );

    final List<StoredDocument> notes = <StoredDocument>[
      (
        id: '${ownerID}_2026-11-15',
        data: <String, dynamic>{
          'ownerID': ownerID,
          'day': '2026-11-15',
          'createdAt': _at,
          'text': 'Late meeting, "again"',
          'triggers': <Object?>['work/meeting', 'tired'],
        },
      ),
      (
        id: '${ownerID}_2026-11-01',
        data: <String, dynamic>{
          'ownerID': ownerID,
          'day': '2026-11-01',
          'createdAt': _at,
          // Would not open: the export keeps its envelope.
          'sealed': Blob(Uint8List.fromList(<int>[1, 2, 3])),
        },
      ),
    ];

    test('day notes are a CSV of their own, by day', () {
      expect(
        exportDayNotesCsv(data(notes: notes)),
        'day,text,triggers,'
        'follow_up_question,follow_up_quote,follow_up_answer\r\n'
        '2026-11-01,,,,,\r\n'
        '2026-11-15,"Late meeting, ""again""",work/meeting; tired,,,\r\n',
      );
      final List<ExportFile> files = exportFiles(
        data(notes: notes),
        DateTime.utc(2026, 11, 15),
      );
      expect(
        files.map((ExportFile f) => f.name),
        contains('penchant-day-notes-2026-11-15.csv'),
      );
    });

    test('someone with no day notes gets no day-notes file', () {
      expect(
        exportFiles(
          data(),
          DateTime.utc(2026, 11, 15),
        ).map((ExportFile f) => f.name),
        isNot(contains(startsWith('penchant-day-notes'))),
      );
    });

    test('the JSON holds every day note field', () {
      final Map<String, dynamic> json =
          jsonDecode(exportJson(data(notes: notes), DateTime.utc(2026)))
              as Map<String, dynamic>;
      final List<dynamic> exported = json['dayNotes'] as List<dynamic>;
      expect(exported, hasLength(2));
      expect(exported.first['text'], 'Late meeting, "again"');
      expect(exported.first['day'], '2026-11-15');
      expect(exported.last['sealed'], base64Encode(<int>[1, 2, 3]));
    });
  });

  test('account deletion and a guest\'s sign-out sweep day notes', () {
    expect(Account.ownedCollections, contains('dayNotes'));
  });

  test('day notes seal text and triggers, and are born sealed', () async {
    expect(contentFields['dayNotes'], <String>[
      'text',
      'triggers',
      'followUpQuestion',
      'followUpQuote',
      'followUpAnswer',
    ]);
    final _Source source = _Source();
    await PlaintextMigrator(source: source, sealer: sealer).run(ownerID);
    expect(source.paged, isNot(contains('dayNotes')));
    expect(source.paged, containsAll(<String>['vices', 'activities']));
  });
}
