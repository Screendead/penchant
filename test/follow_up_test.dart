import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/account/account.dart';
import 'package:tracker/account/export.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/limits.dart';
import 'package:tracker/data/sealed.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/main.dart' show generateRoute;
import 'package:tracker/notes/day_note_route.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/follow_up_setting.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/day_note_sheet.dart';
import 'package:tracker/widgets/note_panels.dart';
import 'package:tracker/widgets/urge_note_fields.dart';
import 'package:tracker/widgets/what_was_going_on_sheet.dart';

import 'fake_sealer.dart';
import 'fake_writes.dart';
import 'fakes.dart';

const String _note = 'Rough one. Boss tore into the roadmap, went to the pub.';
const String _quote = 'went to the pub';
const String _asked = 'Was that already the plan this morning?';
const NoteQuestion _question = (question: _asked, quote: _quote);
const FollowUp _followUp = FollowUp(
  question: _asked,
  quote: _quote,
  answer: 'No, Sam texted at five',
);

Map<String, Object?> _answer({Object? question}) => <String, Object?>{
  'reason': 'ok',
  'tags': <Object?>[],
  'question': ?question,
};

class _Reader implements QuestioningNoteReader {
  _Reader(this.asked);

  final NoteQuestion? asked;
  int reads = 0;

  @override
  Stream<ReadTag> read(String note) {
    reads++;
    return const Stream<ReadTag>.empty();
  }

  @override
  Future<NoteQuestion?> question(String note) async => asked;
}

class _FixedToday extends Today {
  _FixedToday(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

void main() {
  group('CallableNoteReader question', () {
    test(
      'asks in the same one call as the tags, only when switched on',
      () async {
        final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
        final CallableNoteReader reader = CallableNoteReader((data) async {
          sent.add(data);
          return _answer(
            question: <String, Object?>{'question': _asked, 'quote': _quote},
          );
        }, askQuestions: true);
        final Future<NoteQuestion?> question = reader.question(_note);
        expect(await reader.read(_note).toList(), isEmpty);
        expect(await question, _question);
        expect(sent, <Object?>[
          <String, Object?>{'note': _note, 'question': true},
        ]);

        final CallableNoteReader off = CallableNoteReader((data) async {
          sent.add(data);
          return _answer(
            question: <String, Object?>{'question': _asked, 'quote': _quote},
          );
        });
        expect(await off.question(_note), isNull);
        await off.read(_note).toList();
        expect(sent.last, <String, Object?>{'note': _note});
      },
    );

    test(
      'is null when absent, failed, or unverifiable on the device',
      () async {
        Future<NoteQuestion?> asked(Object? answer, [String note = _note]) =>
            CallableNoteReader(
              (_) async => answer,
              askQuestions: true,
            ).question(note);
        Map<String, Object?> q(String question, [String quote = _quote]) =>
            _answer(
              question: <String, Object?>{'question': question, 'quote': quote},
            );

        expect(await asked(_answer()), isNull);
        expect(
          await asked(<String, Object?>{'reason': 'ok', 'question': null}),
          isNull,
        );
        expect(await asked('garbage'), isNull);
        expect(await asked(q(_asked, 'went to the bar')), isNull);
        expect(await asked(q(_asked, 'Went to the pub')), isNull);
        expect(await asked(q('Who was there? Where?')), isNull);
        expect(await asked(q('Tell me who was there.')), isNull);
        expect(await asked(q('Was it after 6?')), isNull);
        expect(await asked(q('${'W' * maxFollowUpQuestionLength}?')), isNull);
        expect(
          await CallableNoteReader(
            (_) async => throw StateError('offline'),
            askQuestions: true,
          ).question(_note),
          isNull,
        );
        expect(await asked(q('  Who else was there?  ')), (
          question: 'Who else was there?',
          quote: _quote,
        ));
      },
    );

    test('a failed call is asked again on the next read', () async {
      int calls = 0;
      final CallableNoteReader reader = CallableNoteReader((_) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return _answer();
      }, askQuestions: true);
      expect(await reader.question(_note), isNull);
      expect(await reader.read(_note).toList(), isEmpty);
      expect(calls, 2);
    });

    test('noteReaderProvider asks only with both switches on', () async {
      Future<bool> asks({required bool followUp}) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          NoteReaderEnabled.key: true,
          FollowUpEnabled.key: followUp,
        });
        final ProviderContainer container = ProviderContainer(
          overrides: [
            userProvider.overrideWith((ref) => Stream.value(FakeUser('a'))),
            claudeAllowedProvider.overrideWithValue(true),
          ],
        );
        addTearDown(container.dispose);
        container.listen(noteReaderProvider, (_, _) {});
        await pumpEventQueue();
        return (container.read(noteReaderProvider)! as CallableNoteReader)
            .askQuestions;
      }

      expect(await asks(followUp: true), isTrue);
      expect(await asks(followUp: false), isFalse);
    });
  });

  group('storage', () {
    test('an entry seals the follow-up and opens it again', () async {
      final FakeSealer sealer = FakeSealer();
      const ActivityContent content = ActivityContent(
        triggers: <String>['place/bar'],
        note: _note,
        followUp: _followUp,
      );
      final Map<String, dynamic> json = <String, dynamic>{
        'viceID': 'v',
        'quantity': 1,
        'ownerID': ownerID,
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 15)),
        sealedField: Blob(
          await sealer.seal(content.toMap(), context: 'activities/a'),
        ),
      };
      final ViceActivity entry = ViceActivity.fromJson(
        id: 'a',
        json: json,
        opened: await SealedOpener(sealer).open('activities', 'a', json),
      );
      expect(entry.followUp, _followUp);
      expect(entry.content.followUp, _followUp);
      // The editor's save rebuilds the content from its answers; it stays.
      final ActivityContent edited = entry.content.withAnswers(
        triggers: const <String>[],
        urge: 3,
        note: 'shorter',
      );
      expect(edited.followUp, _followUp);
      expect(edited.triggersAlone, isFalse);
      expect(edited.withFollowUp(null).answersDiffer(edited), isTrue);
      for (final String field in followUpFields) {
        expect(activityContentFields, contains(field));
        expect(dayNoteContentFields, contains(field));
      }
    });

    test('a day note seals the follow-up and opens it again', () async {
      final FakeSealer sealer = FakeSealer();
      const String id = '${ownerID}_2026-11-15';
      final Map<String, dynamic> json = <String, dynamic>{
        'ownerID': ownerID,
        'day': '2026-11-15',
        sealedField: Blob(
          await sealer.seal(
            dayNoteContent(
              text: _note,
              triggers: const <String>[],
              followUp: _followUp,
            ),
            context: 'dayNotes/$id',
          ),
        ),
      };
      final DayNote note = DayNote.fromJson(
        id: id,
        json: json,
        opened: await SealedOpener(sealer).open(dayNotesCollection, id, json),
      );
      expect(note.followUp, _followUp);
      expect(
        dayNoteContent(text: _note, triggers: const <String>[]).keys,
        <String>['text', 'triggers'],
      );
    });

    test(
      'half a follow-up or a mistyped one reads as none, never throwing',
      () {
        expect(FollowUp.read(<String, Object?>{}), isNull);
        expect(
          FollowUp.read(<String, Object?>{followUpQuestionField: _asked}),
          isNull,
        );
        expect(
          FollowUp.read(<String, Object?>{followUpAnswerField: 'x'}),
          isNull,
        );
        expect(
          FollowUp.read(<String, Object?>{
            followUpQuestionField: 3,
            followUpAnswerField: 'x',
          }),
          isNull,
        );
        expect(
          FollowUp.read(<String, Object?>{
            followUpQuestionField: _asked,
            followUpQuoteField: 7,
            followUpAnswerField: 'x',
          }),
          const FollowUp(question: _asked, answer: 'x'),
        );
        expect(FollowUp.answered(_question, '   '), isNull);
        expect(FollowUp.answered(null, 'x'), isNull);
      },
    );

    test('an overlong answer is refused, on an entry and a day note', () {
      final FollowUp long = FollowUp(
        question: _asked,
        quote: _quote,
        answer: 'x' * (maxFollowUpAnswerLength + 1),
      );
      expect(
        answersTooLong(
          triggers: const <String>[],
          urge: null,
          note: _note,
          followUp: long,
        ),
        isNotNull,
      );
      expect(dayNoteError(_note, const <String>[], followUp: long), isNotNull);
      expect(
        answersTooLong(
          triggers: const <String>[],
          urge: null,
          note: _note,
          followUp: _followUp,
        ),
        isNull,
      );
    });

    test('the exports append the follow-up columns', () {
      final Map<String, Object?> sealedContent = _followUp.toMap();
      final AccountData data = AccountData(
        vices: const <StoredDocument>[],
        activities: <StoredDocument>[
          (
            id: 'a',
            data: <String, dynamic>{
              'viceID': 'v',
              'quantity': 1,
              'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 2)),
              ...sealedContent,
            },
          ),
        ],
        dayNotes: <StoredDocument>[
          (
            id: 'd',
            data: <String, dynamic>{
              'day': '2026-11-02',
              'text': 'A day',
              ...sealedContent,
            },
          ),
        ],
      );
      final int asked = csvHeader.indexOf('follow_up_question');
      expect(asked, csvHeader.indexOf('logged_via') + 1);
      expect(csvHeader.sublist(asked, asked + 3), <String>[
        'follow_up_question',
        'follow_up_quote',
        'follow_up_answer',
      ]);
      expect(dayNotesCsvHeader.take(3), <String>['day', 'text', 'triggers']);
      const String tail = ',$_asked,$_quote,"No, Sam texted at five"';
      // The strength columns follow, blank here.
      expect(exportCsv(data).split('\r\n')[1], endsWith('$tail,,,,'));
      expect(exportDayNotesCsv(data).split('\r\n')[1], endsWith(tail));
    });
  });

  group('the follow-up panel after a log', () {
    late WhatWasGoingOnPick? done;

    Future<void> pump(WidgetTester tester, NoteReader? reader) async {
      done = null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[noteReaderProvider.overrideWithValue(reader)],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 600),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: WhatWasGoingOnSheet(
                    viceName: 'Wine',
                    onDone: (WhatWasGoingOnPick p) => done = p,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> tap(WidgetTester tester, Key key) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    Future<void> toTags(WidgetTester tester) async {
      await tester.enterText(find.byKey(NoteField.fieldKey), _note);
      await tap(tester, NotePanels.nextKey);
    }

    testWidgets(
      'comes after the tags only with a question, counted from then',
      (tester) async {
        await pump(tester, _Reader(_question));
        expect(find.text('1 of 3'), findsOneWidget);
        await toTags(tester);
        expect(find.text('2 of 4'), findsOneWidget);
        await tap(tester, NotePanels.nextKey);
        expect(find.text('3 of 4'), findsOneWidget);
        expect(find.text(NotePanels.followUpTitle), findsOneWidget);
        expect(find.text('You wrote “$_quote”. $_asked'), findsOneWidget);
        final RichText marked = tester
            .widgetList<RichText>(find.byType(RichText))
            .firstWhere((RichText t) => t.text.toPlainText() == _note);
        bool lit = false;
        marked.text.visitChildren((InlineSpan s) {
          if (s is TextSpan && s.text == _quote) {
            lit = s.style?.background != null;
          }
          return true;
        });
        expect(lit, isTrue);
        await tap(tester, NotePanels.nextKey);
        expect(find.text('4 of 4'), findsOneWidget);
        expect(find.byKey(UrgeField.keyFor(1)), findsOneWidget);
      },
    );

    testWidgets('with no question the flow is as before', (tester) async {
      await pump(tester, _Reader(null));
      await toTags(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      await tap(tester, NotePanels.nextKey);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text(NotePanels.followUpTitle), findsNothing);
    });

    testWidgets('a question whose quote is not in the note is not shown', (
      tester,
    ) async {
      await pump(tester, _Reader((question: _asked, quote: 'the bar')));
      await toTags(tester);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('an answer is saved with its question', (tester) async {
      await pump(tester, _Reader(_question));
      await toTags(tester);
      await tap(tester, NotePanels.nextKey);
      await tester.enterText(
        find.byKey(NotePanels.answerKey),
        _followUp.answer,
      );
      await tap(tester, NotePanels.doneKey);
      expect(done?.note, _note);
      expect(done?.followUp, _followUp);
    });

    testWidgets('Skip saves nothing extra', (tester) async {
      await pump(tester, _Reader(_question));
      await toTags(tester);
      await tap(tester, NotePanels.nextKey);
      await tester.enterText(find.byKey(NotePanels.answerKey), 'typed');
      await tap(tester, NotePanels.skipKey);
      expect(find.byKey(UrgeField.keyFor(1)), findsOneWidget);
      await tap(tester, NotePanels.doneKey);
      expect(done?.note, _note);
      expect(done?.followUp, isNull);
    });

    testWidgets('editing the note after the question drops it', (tester) async {
      await pump(tester, _Reader(_question));
      await toTags(tester);
      await tap(tester, NotePanels.nextKey);
      await tester.enterText(find.byKey(NotePanels.answerKey), 'typed');
      await tap(tester, NotePanels.backKey);
      await tap(tester, NotePanels.backKey);
      await tester.enterText(find.byKey(NoteField.fieldKey), 'Something else');
      await tap(tester, NotePanels.doneKey);
      expect(done?.followUp, isNull);
    });
  });

  group('the follow-up panel on a day note', () {
    late FakeTrackerWrites writes;
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    final DateTime today = DateTime(2026, 11, 15);

    Future<void> open(
      WidgetTester tester, {
      NoteReader? reader,
      DayNote? note,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            trackerWritesProvider.overrideWithValue(writes),
            memoryJournal(),
            userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
            todayProvider.overrideWith(() => _FixedToday(today)),
            noteReaderProvider.overrideWithValue(reader),
            dayNoteProvider.overrideWith(
              (Ref ref, DateTime day) => AsyncData<DayNote?>(note),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: appTheme(Brightness.light),
            onGenerateRoute: generateRoute,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                ref.watch(userProvider);
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      unawaited(navigator.currentState!.pushNamed(dayNoteRoute(today)));
      await tester.pumpAndSettle();
    }

    setUp(() => writes = FakeTrackerWrites());

    Future<void> tap(WidgetTester tester, Key key) async {
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    testWidgets('is the third of three, and its answer is saved', (
      tester,
    ) async {
      await open(tester, reader: _Reader(_question));
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.enterText(find.byKey(DayNoteSheet.fieldKey), _note);
      await tap(tester, NotePanels.nextKey);
      expect(find.text('2 of 3'), findsOneWidget);
      await tap(tester, NotePanels.nextKey);
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.enterText(
        find.byKey(NotePanels.answerKey),
        _followUp.answer,
      );
      await tap(tester, NotePanels.doneKey);
      expect(writes.writes.single.fields['followUp'], _followUp.toMap());
    });

    testWidgets('Skip on the last panel saves the note alone', (tester) async {
      await open(tester, reader: _Reader(_question));
      await tester.enterText(find.byKey(DayNoteSheet.fieldKey), _note);
      await tap(tester, NotePanels.nextKey);
      await tap(tester, NotePanels.nextKey);
      await tap(tester, NotePanels.skipKey);
      expect(writes.writes.single.fields['text'], _note);
      expect(writes.writes.single.fields.containsKey('followUp'), isFalse);
    });

    testWidgets('a saved follow-up shows under the note and is kept on save', (
      tester,
    ) async {
      await open(
        tester,
        note: DayNote(
          id: dayNoteID(ownerID, dayKey(today)),
          ownerID: ownerID,
          day: dayKey(today),
          createdAt: Timestamp.fromDate(today),
          text: _note,
          followUp: _followUp,
        ),
      );
      expect(find.byKey(DayNoteSheet.savedFollowUpKey), findsOneWidget);
      expect(find.text(_followUp.answer), findsOneWidget);
      await tap(tester, NotePanels.doneKey);
      expect(writes.writes.single.fields['followUp'], _followUp.toMap());
    });
  });

  group('FollowUpSetting', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required bool reader,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        NoteReaderEnabled.key: reader,
      });
      final ProviderContainer container = ProviderContainer(
        overrides: [claudeAllowedProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const Scaffold(body: FollowUpSetting()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('is disabled, saying why, while the note reader is off', (
      tester,
    ) async {
      final ProviderContainer container = await pump(tester, reader: false);
      expect(find.text(FollowUpSetting.needsReader), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(FollowUpSetting.disclosureTitle), findsNothing);
      expect(container.read(followUpEnabledProvider), isFalse);
    });

    testWidgets('is off by default and turns on only after the disclosure', (
      tester,
    ) async {
      final ProviderContainer container = await pump(tester, reader: true);
      expect(container.read(followUpEnabledProvider), isFalse);
      expect(find.text(FollowUpSetting.subtitle), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(FollowUpSetting.disclosure), findsOneWidget);
      await tester.tap(find.text(FollowUpSetting.notNow));
      await tester.pumpAndSettle();
      expect(container.read(followUpEnabledProvider), isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text(FollowUpSetting.turnOn));
      await tester.pumpAndSettle();
      expect(container.read(followUpEnabledProvider), isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(FollowUpEnabled.key), isTrue);
    });
  });
}
