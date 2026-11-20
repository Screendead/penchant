import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/errors/not_found.dart';
import 'package:tracker/main.dart' show generateRoute, routePage;
import 'package:tracker/notes/day_note_route.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/widgets/day_note_sheet.dart';
import 'package:tracker/widgets/note_panels.dart';
import 'package:tracker/writes/settle_write.dart';

import 'fake_writes.dart';
import 'fakes.dart';

class _FixedToday extends Today {
  _FixedToday(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

class _FakeReader implements NoteReader {
  final StreamController<ReadTag> tags = StreamController<ReadTag>();

  @override
  Stream<ReadTag> read(String note) => tags.stream;
}

final DateTime _today = DateTime(2026, 11, 15);
final DateTime _yesterday = DateTime(2026, 11, 14);

DayNote _note({
  String text = 'Rough night\nthen a long meeting',
  List<String> triggers = const <String>['work/meeting'],
  bool locked = false,
}) => DayNote(
  id: dayNoteID(ownerID, dayKey(_yesterday)),
  ownerID: ownerID,
  day: dayKey(_yesterday),
  createdAt: Timestamp.fromDate(_yesterday),
  text: locked ? '' : text,
  triggers: locked ? const <String>[] : triggers,
  locked: locked,
);

void main() {
  late FakeTrackerWrites writes;
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  Future<void> open(
    WidgetTester tester, {
    AsyncValue<DayNote?> note = const AsyncData<DayNote?>(null),
    NoteReader? reader,
    bool still = true,
    Widget? home,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          trackerWritesProvider.overrideWithValue(writes),
          memoryJournal(),
          userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
          todayProvider.overrideWith(() => _FixedToday(_today)),
          noteReaderProvider.overrideWithValue(reader),
          dayNoteProvider.overrideWith((Ref ref, DateTime day) => note),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: appTheme(Brightness.light),
          onGenerateRoute: generateRoute,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: child!,
          ),
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              ref.watch(userProvider);
              return home ?? const Scaffold();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    if (home != null) return;
    unawaited(navigator.currentState!.pushNamed(dayNoteRoute(_yesterday)));
    if (note.hasValue) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Finder field() => find.byKey(DayNoteSheet.fieldKey);

  setUp(() => writes = FakeTrackerWrites());

  group('route', () {
    Widget page(String name) =>
        routePage(name, now: _today.add(const Duration(hours: 9)));

    test('opens the sheet on a past or current day', () {
      expect(
        (page('/day-notes/2026-11-14') as DayNoteSheet).day,
        DateTime(2026, 11, 14),
      );
      expect((page('/day-notes/2026-11-15') as DayNoteSheet).day, _today);
      expect(page(dayNoteRoute(DateTime(2025, 2, 28))), isA<DayNoteSheet>());
    });

    test('a malformed or future date is not found', () {
      for (final String name in <String>[
        '/day-notes/2026-11-16',
        '/day-notes/2026-02-30',
        '/day-notes/2026-13-01',
        '/day-notes/2026-1-01',
        '/day-notes/20261115',
        '/day-notes/2026-11-15/edit',
        '/day-notes',
      ]) {
        expect(page(name), isA<NotFound>(), reason: name);
      }
    });
  });

  testWidgets('a new note is created from the first panel\'s Done', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.byKey(DayNoteSheet.deleteKey), findsNothing);
    await tester.enterText(field(), '  Slept badly\nthen the review  ');
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pumpAndSettle();
    final Write write = writes.writes.single;
    expect(write.op, 'setDayNote');
    expect(write.id, dayNoteID(ownerID, '2026-11-14'));
    expect(write.fields, <String, Object?>{
      'day': '2026-11-14',
      'text': 'Slept badly\nthen the review',
      'triggers': isEmpty,
      'replacing': false,
    });
    expect(field(), findsNothing);
    expect(find.text(DayNoteSheet.savedMessage), findsOneWidget);
  });

  testWidgets('an existing note prefills both panels and Done replaces it', (
    WidgetTester tester,
  ) async {
    await open(tester, note: AsyncData<DayNote?>(_note()));
    expect(find.text('Rough night\nthen a long meeting'), findsOneWidget);
    await tester.tap(find.byKey(NotePanels.nextKey));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.textContaining('Meeting'), findsWidgets);
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pumpAndSettle();
    expect(writes.writes.single.op, 'setDayNote');
    expect(writes.writes.single.fields['replacing'], true);
    expect(writes.writes.single.fields['triggers'], <String>['work/meeting']);
  });

  testWidgets('an existing note can be deleted after confirming', (
    WidgetTester tester,
  ) async {
    await open(tester, note: AsyncData<DayNote?>(_note()));
    await tester.tap(find.byKey(DayNoteSheet.deleteKey));
    await tester.pumpAndSettle();
    expect(find.text(DayNoteSheet.confirmDelete), findsOneWidget);
    expect(writes.writes, isEmpty);
    await tester.tap(find.byKey(DayNoteSheet.confirmDeleteKey));
    await tester.pumpAndSettle();
    expect(writes.writes, <Write>[
      Write('deleteDayNote', dayNoteID(ownerID, '2026-11-14')),
    ]);
    expect(find.text(DayNoteSheet.deletedMessage), findsOneWidget);
  });

  testWidgets('a locked note offers only Delete', (WidgetTester tester) async {
    await open(tester, note: AsyncData<DayNote?>(_note(locked: true)));
    expect(find.text(DayNoteSheet.lockedMessage), findsOneWidget);
    expect(field(), findsNothing);
    expect(find.byKey(NotePanels.nextKey), findsNothing);
    expect(find.byKey(NotePanels.doneKey), findsNothing);
    await tester.tap(find.byKey(DayNoteSheet.deleteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DayNoteSheet.confirmDeleteKey));
    await tester.pumpAndSettle();
    expect(writes.writes.single.op, 'deleteDayNote');
  });

  testWidgets('with no journal key it says so and keeps the text', (
    WidgetTester tester,
  ) async {
    writes.canCreate = false;
    await open(tester);
    await tester.enterText(field(), 'A long day');
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pumpAndSettle();
    expect(find.text('Not saved. $noJournalKeyMessage'), findsOneWidget);
    expect(find.text('A long day'), findsOneWidget);
    expect(writes.writes, isEmpty);
  });

  testWidgets('a refused save keeps the sheet open', (
    WidgetTester tester,
  ) async {
    writes.respond = (_) => Future<void>.error(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await open(tester);
    await tester.enterText(field(), 'A long day');
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not saved.'), findsOneWidget);
    expect(field(), findsOneWidget);
  });

  testWidgets('an unanswered save says it is queued', (
    WidgetTester tester,
  ) async {
    writes.respond = (_) => Completer<void>().future;
    await open(tester);
    await tester.enterText(field(), 'A long day');
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pump(writeTimeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(field(), findsNothing);
    expect(find.text(queuedMessage), findsOneWidget);
  });

  testWidgets('the reader turns the text into tags', (
    WidgetTester tester,
  ) async {
    final _FakeReader reader = _FakeReader();
    await open(tester, reader: reader);
    expect(find.text(NotePanels.readsHint), findsOneWidget);
    await tester.enterText(field(), 'Out of the meeting, went to the pub');
    await tester.tap(find.byKey(NotePanels.nextKey));
    await tester.pumpAndSettle();
    expect(find.text(NotePanels.readingLine), findsOneWidget);
    reader.tags.add((path: 'work/meeting', quote: 'meeting'));
    await reader.tags.close();
    await tester.pumpAndSettle();
    expect(find.text(NotePanels.tagsTitle), findsOneWidget);
    expect(find.text(NotePanels.readLine), findsOneWidget);
    await tester.tap(find.byKey(NotePanels.doneKey));
    await tester.pumpAndSettle();
    expect(writes.writes.single.fields['triggers'], <String>['work/meeting']);
  });

  test('day keys round-trip', () {
    expect(parseDayKey('2026-11-15'), _today);
    expect(parseDayKey('2026-02-30'), isNull);
    expect(dayKey(parseDayKey('2024-02-29')!), '2024-02-29');
    expect(startOfDay(parseDayKey('2026-03-29')!), DateTime(2026, 3, 29));
  });
}
