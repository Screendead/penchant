import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/firebase_init.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/notes/day_note_route.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/widgets/day_note_line.dart';
import 'package:tracker/widgets/day_note_sheet.dart';
import 'package:tracker/widgets/note_panels.dart';
import 'package:tracker/writes/rejected_writes.dart';

import 'support.dart';

// Reads each of [tags] whose quote the note holds, as the real reader only
// emits quotes copied from the note, and asks [asked] about a note holding
// its quote.
class _FakeNoteReader implements QuestioningNoteReader {
  const _FakeNoteReader(this.tags, this.asked);

  final List<ReadTag> tags;
  final NoteQuestion asked;

  @override
  Stream<ReadTag> read(String note) => Stream<ReadTag>.fromIterable(
    tags.where((ReadTag t) => note.contains(t.quote)),
  );

  @override
  Future<NoteQuestion?> question(String note) async =>
      note.contains(asked.quote) ? asked : null;
}

const NoteQuestion _asked = (
  question: 'What kept it going?',
  quote: 'ran late',
);
const String _answer = 'Nobody wanted to be first to leave';

const String _meeting = 'work/meeting';
const String _friends = 'social/friends';
const String _meetingChip = 'Work or study › Meeting';
const String _friendsChip = 'Who was there › With friends';

void main() {
  ensureE2EBinding();

  setUpAll(() async {
    requireEmulators();
    await initializeFirebase();
    await clearEmulators();
  });

  testWidgets('a day note is created, tagged, edited and deleted under the '
      'rules', (WidgetTester tester) async {
    await tester.pumpWidget(
      e2eApp(
        overrides: <Override>[
          noteReaderProvider.overrideWithValue(
            const _FakeNoteReader(<ReadTag>[
              (path: _meeting, quote: 'meeting'),
              (path: _friends, quote: 'friends'),
            ], _asked),
          ),
        ],
      ),
    );
    await register(tester, 'e2e-day-note@example.com');
    // Today with no habits is the empty start, without the note's line.
    await addVicesThroughManageData(tester, const <String>['Coffee']);

    final String uid = FirebaseAuth.instance.currentUser!.uid;
    final DateTime today = DateTime.now();
    final String id = dayNoteID(uid, dayKey(today));
    final Finder sheet = find.byType(DayNoteSheet);
    final Finder field = find.byKey(DayNoteSheet.fieldKey);
    final Finder todayLine = find.descendant(
      of: find.byType(DayNoteLine),
      matching: find.byType(InkWell),
    );

    void expectNoRejections() {
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(Homepage, skipOffstage: false)),
      );
      expect(container.read(rejectedWritesProvider), isEmpty);
    }

    Future<Map<String, Object?>> stored() async {
      await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(dayNotesCollection)
          .doc(id)
          .get(const GetOptions(source: Source.server));
      expect(doc.exists, isTrue, reason: 'dayNotes/$id');
      expect(doc.data()!.keys.toSet(), <String>{
        sealedField,
        'ownerID',
        'day',
        'createdAt',
        'updatedAt',
      });
      expect(doc.data()!['updatedAt'], isA<Timestamp>());
      expect(doc.data()!['day'], dayKey(today));
      return storedContent(doc);
    }

    Finder chip(String label) => find.widgetWithText(FilterChip, label);

    Future<void> waitForChips(List<String> labels) async {
      for (final String label in labels) {
        await pumpUntil(tester, chip(label).hitTestable());
      }
      await pumpUntil(tester, find.text(NotePanels.readLine));
    }

    Future<void> doneAndSaved(String message) async {
      await tap(tester, find.byKey(NotePanels.doneKey));
      await pumpUntil(tester, sheet, present: false);
      await pumpUntil(tester, find.text(message));
      expectNoRejections();
    }

    Future<void> waitForField(String text) => pumpUntilTrue(
      tester,
      () =>
          field.evaluate().isNotEmpty &&
          tester
                  .widget<EditableText>(
                    find.descendant(
                      of: field,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text ==
              text,
      () => 'the note field to hold "$text"',
    );

    // Create, with both read tags kept.
    const String first = 'Long meeting ran late, then drinks with friends';
    unawaited(
      Navigator.of(
        tester.element(find.byType(Homepage)),
      ).pushNamed(dayNoteRoute(today)),
    );
    await pumpUntilRouteSettled(tester, sheet);
    await waitForField('');
    await tester.enterText(field, first);
    await tester.pump();
    await tap(tester, find.byKey(NotePanels.nextKey));
    await waitForChips(const <String>[_meetingChip, _friendsChip]);
    expect(tester.widget<FilterChip>(chip(_meetingChip)).selected, isTrue);
    expect(tester.widget<FilterChip>(chip(_friendsChip)).selected, isTrue);
    // The question adds a panel after the tags; answer it.
    await pumpUntil(tester, find.byKey(NotePanels.nextKey).hitTestable());
    await tap(tester, find.byKey(NotePanels.nextKey));
    final Finder answer = find.byKey(NotePanels.answerKey);
    await pumpUntil(tester, answer.hitTestable());
    expect(
      find.text(askedLine(_asked.question, _asked.quote)).hitTestable(),
      findsOneWidget,
    );
    await tester.enterText(answer, _answer);
    await tester.pump();
    await doneAndSaved(DayNoteSheet.savedMessage);
    Map<String, Object?> content = await stored();
    expect(content[dayNoteTextField], first);
    expect(content['triggers'], <Object?>[_meeting, _friends]);
    expect(content[followUpQuestionField], _asked.question);
    expect(content[followUpQuoteField], _asked.quote);
    expect(content[followUpAnswerField], _answer);
    await pumpUntil(tester, todayLine);

    // Update from Today's line: new text, one read tag dropped.
    const String second = 'Short meeting, no drinks with friends after all';
    await tap(tester, todayLine);
    await pumpUntilRouteSettled(tester, sheet);
    await waitForField(first);
    // The saved question and answer show under the note.
    await pumpUntil(tester, find.byKey(DayNoteSheet.savedFollowUpKey));
    expect(
      find.descendant(
        of: find.byKey(DayNoteSheet.savedFollowUpKey),
        matching: find.text(askedLine(_asked.question, _asked.quote)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(DayNoteSheet.savedFollowUpKey),
        matching: find.text(_answer),
      ),
      findsOneWidget,
    );
    await tester.enterText(field, second);
    await tester.pump();
    await tap(tester, find.byKey(NotePanels.nextKey));
    await waitForChips(const <String>[_meetingChip, _friendsChip]);
    await tap(tester, chip(_friendsChip));
    await pumpUntilTrue(
      tester,
      () => !tester.widget<FilterChip>(chip(_friendsChip)).selected,
      () => 'the dropped chip to clear',
    );
    expect(tester.widget<FilterChip>(chip(_meetingChip)).selected, isTrue);
    await doneAndSaved(DayNoteSheet.savedMessage);
    content = await stored();
    expect(content[dayNoteTextField], second);
    expect(content['triggers'], <Object?>[_meeting]);

    // Delete.
    await tap(tester, todayLine);
    await pumpUntilRouteSettled(tester, sheet);
    await waitForField(second);
    await tap(tester, find.byKey(DayNoteSheet.deleteKey));
    await tap(tester, find.byKey(DayNoteSheet.confirmDeleteKey));
    await pumpUntil(tester, sheet, present: false);
    await pumpUntil(tester, find.text(DayNoteSheet.deletedMessage));
    expectNoRejections();
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(timeout);
    expect(await existsBypassingRules(dayNotesCollection, id), isFalse);
    await pumpUntil(tester, todayLine, present: false);
    expectNoRejections();
  });
}
