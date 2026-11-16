import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/older_notes.dart';
import 'package:tracker/providers/device_files_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fake_sealer.dart';
import 'fake_writes.dart';
import 'fakes.dart';

ViceActivity entry(
  String id, {
  String? note = 'boss tore into the roadmap, went to the pub',
  List<String> triggers = const <String>[],
  int day = 1,
  bool locked = false,
}) => ViceActivity(
  id: id,
  viceID: 'v1',
  quantity: 1,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime(2026, 10, day, 20)),
  note: note,
  triggers: triggers,
  locked: locked,
);

/// Answers each note from [answers] once [gate] (if any) completes.
class FakeReader implements NoteReader {
  FakeReader(this.answers);

  final Map<String, List<ReadTag>> answers;
  final List<String> sent = <String>[];
  Completer<void>? gate;

  @override
  Stream<ReadTag> read(String note) async* {
    sent.add(note);
    await gate?.future;
    yield* Stream<ReadTag>.fromIterable(answers[note] ?? const <ReadTag>[]);
  }
}

void main() {
  group('choosing notes', () {
    test('leaves out locked, read, empty and full entries, newest first', () {
      final OlderNotesProgress p = OlderNotesProgress(
        done: const <String>{'read'},
        proposals: const <String, List<ReadTag>>{
          'pending': <ReadTag>[(path: 'work/meeting', quote: 'boss')],
        },
      );
      final OlderNotes n = olderNotes(<ViceActivity>[
        entry('old', day: 1),
        entry('new', day: 5),
        entry('locked', locked: true),
        entry('read'),
        entry('pending'),
        entry('blank', note: '  '),
        entry('none', note: null),
        entry('full', triggers: List<String>.generate(10, (int i) => 't$i')),
      ], p);
      expect(
        <String>[for (final ViceActivity e in n.unread) e.id],
        <String>['new', 'old'],
      );
      expect(n.locked, 1);
      expect(n.full, 1);
      expect(n.read, 2);
    });

    test('shows only tags quoted in the note as it is now, not already '
        'there, and no more than there is room for', () {
      final ViceActivity e = entry(
        'a',
        triggers: List<String>.generate(8, (int i) => 't$i')
          ..add('social/friends'),
      );
      expect(
        shownTags(e, <ReadTag>[
          (path: 'social/friends', quote: 'pub'),
          (path: 'feeling/stressed', quote: 'not in it'),
          (path: 'people/criticised', quote: 'boss tore into'),
          (path: 'work/meeting', quote: 'roadmap'),
        ]),
        <ReadTag>[(path: 'people/criticised', quote: 'boss tore into')],
      );
    });

    test('withTags adds new paths while there is room', () {
      expect(withTags(<String>['a'], <String>['a', 'b']), <String>['a', 'b']);
      expect(
        withTags(List<String>.generate(10, (int i) => '$i'), <String>['x']),
        hasLength(10),
      );
    });

    test('progress survives its JSON and counts per local day', () {
      final DateTime now = DateTime(2026, 11, 16, 9);
      final OlderNotesProgress p = const OlderNotesProgress()
          .counted(now)
          .read('a', <ReadTag>[(path: 'work/meeting', quote: 'boss')])
          .read('b', const <ReadTag>[]);
      final OlderNotesProgress back = OlderNotesProgress.fromJson(p.toJson());
      expect(back.done, <String>{'b'});
      expect(back.proposals['a'], <ReadTag>[
        (path: 'work/meeting', quote: 'boss'),
      ]);
      expect(back.leftToday(now), olderNotesDailyCap - 1);
      expect(back.leftToday(DateTime(2026, 11, 17)), olderNotesDailyCap);
      expect(back.decided(<String>['a']).proposals, isEmpty);
    });
  });

  group('the runner', () {
    late Directory dir;
    late FakeTrackerWrites writes;
    late FakeReader reader;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('older-notes-test');
      writes = FakeTrackerWrites();
      reader = FakeReader(<String, List<ReadTag>>{
        'boss tore into the roadmap, went to the pub': <ReadTag>[
          (path: 'people/criticised', quote: 'boss tore into'),
        ],
      });
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<ProviderContainer> start() async {
      final SealedFiles files = DeviceFiles(
        caches: () async => dir,
        support: () async => dir,
      ).keptForUser(ownerID, FakeFileSealer());
      final ProviderContainer c = ProviderContainer(
        overrides: [
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(MemoryJournalStore()),
          keptSealedFilesProvider.overrideWithValue(files),
          olderNoteReaderProvider.overrideWithValue(reader),
        ],
      );
      addTearDown(c.dispose);
      c.listen(olderNotesProvider, (_, _) {});
      await c.read(userProvider.future);
      // Progress is read from a real file, which the event queue alone does
      // not wait for.
      for (int i = 0; i < 200; i++) {
        if (c.read(olderNotesProvider).progress != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.read(olderNotesProvider).progress, isNotNull);
      return c;
    }

    test('a batch keeps what it read, in the sealed file', () async {
      final ProviderContainer c = await start();
      final ClaudeWork work = ClaudeWork(status: 'Reading');
      await c.read(olderNotesProvider.notifier).read(<ViceActivity>[
        entry('a'),
        entry('b', note: 'quiet night'),
      ], work: work);
      expect(reader.sent, hasLength(2));
      expect(work.end, ClaudeWorkEnd.answered);
      final OlderNotesProgress p = c.read(olderNotesProvider).progress!;
      expect(p.proposals.keys, <String>['a']);
      expect(p.done, <String>{'b'});

      final ProviderContainer again = await start();
      expect(again.read(olderNotesProvider).progress!.proposals.keys, <String>[
        'a',
      ]);
      expect(
        again.read(olderNotesProvider).progress!.leftToday(DateTime.now()),
        olderNotesDailyCap - 2,
      );
    });

    test('Stop drops the note in flight, which stays unread', () async {
      final ProviderContainer c = await start();
      reader.gate = Completer<void>();
      final ClaudeWork work = ClaudeWork(status: 'Reading');
      final Future<void> run = c.read(olderNotesProvider.notifier).read(
        <ViceActivity>[entry('a'), entry('b')],
        work: work,
      );
      await pumpEventQueue();
      c.read(olderNotesProvider.notifier).stop();
      reader.gate!.complete();
      await run;
      expect(reader.sent, hasLength(1));
      expect(work.end, ClaudeWorkEnd.stopped);
      final OlderNotesProgress p = c.read(olderNotesProvider).progress!;
      expect(p.seen('a'), isFalse);
      expect(c.read(olderNotesProvider).reading, isFalse);
    });

    test('keeping tags reseals the whole content and marks the note '
        'decided', () async {
      final ProviderContainer c = await start();
      final ViceActivity a = entry('a', triggers: const <String>['bored af']);
      writes.cached['a'] = ActivityContent(
        triggers: const <String>['bored af'],
        urge: 4,
        note: a.note,
        zone: 'Europe/London',
        writtenAt: DateTime.utc(2026, 10, 1, 19),
        loggedVia: LoggedVia.sheet,
        followUp: const FollowUp(question: 'Who was there?', answer: 'Sam'),
      );
      final OlderNotesRunner runner = c.read(olderNotesProvider.notifier);
      await runner.read(<ViceActivity>[a]);
      final TagSaves saved = await runner.decide(
        <String, List<String>>{
          'a': <String>['people/criticised'],
        },
        <String, ViceActivity>{'a': a},
        what: (_) => 'Tags not saved',
      );
      expect(saved.saved, 1);
      final ActivityContent sealed = writes.sealed['a']!;
      expect(sealed.triggers, <String>['bored af', 'people/criticised']);
      expect(sealed.urge, 4);
      expect(sealed.note, a.note);
      expect(sealed.zone, 'Europe/London');
      expect(sealed.writtenAt, DateTime.utc(2026, 10, 1, 19));
      expect(sealed.loggedVia, LoggedVia.sheet);
      expect(sealed.followUp?.answer, 'Sam');
      final OlderNotesProgress p = c.read(olderNotesProvider).progress!;
      expect(p.done, contains('a'));
      expect(p.proposals, isEmpty);
    });

    test('a save that fails at once keeps the note for review', () async {
      final ProviderContainer c = await start();
      final ViceActivity a = entry('a');
      writes.canCreate = false;
      final OlderNotesRunner runner = c.read(olderNotesProvider.notifier);
      await runner.read(<ViceActivity>[a]);
      final TagSaves saved = await runner.decide(
        <String, List<String>>{
          'a': <String>['people/criticised'],
        },
        <String, ViceActivity>{'a': a},
        what: (_) => 'Tags not saved',
      );
      expect(saved.failed, 1);
      expect(writes.writes, isEmpty);
      expect(c.read(olderNotesProvider).progress!.proposals.keys, <String>[
        'a',
      ]);
    });

    test('dropping writes nothing and is never offered again', () async {
      final ProviderContainer c = await start();
      final ViceActivity a = entry('a');
      final OlderNotesRunner runner = c.read(olderNotesProvider.notifier);
      await runner.read(<ViceActivity>[a]);
      await runner.decide(
        <String, List<String>>{'a': const <String>[]},
        <String, ViceActivity>{'a': a},
        what: (_) => 'x',
      );
      expect(writes.writes, isEmpty);
      final OlderNotesProgress p = c.read(olderNotesProvider).progress!;
      expect(olderNotes(<ViceActivity>[a], p).unread, isEmpty);
    });
  });
}
