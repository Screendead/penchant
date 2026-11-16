// Tag older notes (start and review) and Tidy my tags (the labels to send and
// the suggestions), checked as widgets and, given a directory, rendered at
// 390x844 in light and dark to PNGs:
//   flutter test test/tag_notes_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/crypto/sealed_files.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/older_notes.dart';
import 'package:tracker/notes/older_notes_page.dart';
import 'package:tracker/notes/tag_tidy.dart';
import 'package:tracker/notes/tag_tidy_page.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fake_sealer.dart';
import 'fake_writes.dart';
import 'fakes.dart';
import 'insights_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = DateTime(2026, 11, 16);

ViceActivity _entry(
  String id,
  String viceID,
  int day,
  String? note, {
  List<String> triggers = const <String>[],
}) => ViceActivity(
  id: id,
  viceID: viceID,
  quantity: 1,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime(2026, 10, day, 20, 30)),
  note: note,
  triggers: triggers,
);

final List<ViceActivity> _entries = <ViceActivity>[
  _entry(
    'a',
    'wine',
    3,
    'Quarterly review ran late, boss tore into the roadmap. Went to the pub '
        'with Sam after.',
    triggers: const <String>['hungover'],
  ),
  _entry('b', 'coffee', 4, 'Baby up all night, third coffee before ten.'),
  _entry('c', 'wine', 5, 'Sunday roast at mum’s, a couple of glasses.'),
  for (int i = 0; i < 40; i++) _entry('old$i', 'coffee', 6 + i % 20, 'Note $i'),
  _entry('d', 'wine', 9, null, triggers: const <String>['hung over', 'bday']),
  _entry('e', 'wine', 10, null, triggers: const <String>['work stress']),
  _entry(
    'f',
    'coffee',
    11,
    null,
    triggers: const <String>['stressed about work', 'so bored'],
  ),
  _entry('g', 'wine', 12, null, triggers: const <String>['hungover', 'payday']),
];

final List<DayNote> _dayNotes = <DayNote>[
  DayNote(
    id: dayNoteID(ownerID, '2026-10-12'),
    ownerID: ownerID,
    day: '2026-10-12',
    createdAt: Timestamp.fromDate(DateTime(2026, 10, 12)),
    text: 'Long day.',
    triggers: const <String>['bored af', 'pay day'],
  ),
];

final OlderNotesProgress _review = OlderNotesProgress(
  done: <String>{for (int i = 0; i < 12; i++) 'old$i'},
  proposals: const <String, List<ReadTag>>{
    'a': <ReadTag>[
      (path: 'work/meeting', quote: 'Quarterly review'),
      (path: 'people/criticised', quote: 'boss tore into the roadmap'),
      (path: 'social/friends', quote: 'with Sam'),
    ],
    'b': <ReadTag>[(path: 'social/kids', quote: 'Baby up all night')],
  },
  day: '2026-11-16',
  sent: 14,
);

class _FixedRunner extends OlderNotesRunner {
  _FixedRunner(this.fixed);

  final OlderNotesProgress fixed;

  @override
  OlderNotesState build() => OlderNotesState(progress: fixed);
}

class _FakeReader implements NoteReader {
  @override
  Stream<ReadTag> read(String note) => const Stream<ReadTag>.empty();
}

class _FakeTidier implements TagTidier {
  final List<List<String>> sent = <List<String>>[];

  @override
  Future<List<TidySuggestion>> tidy(List<String> labels) async {
    sent.add(labels);
    return const <TidySuggestion>[
      TidySuggestion(
        from: <String>['hungover', 'hung over'],
        label: 'hungover',
      ),
      TidySuggestion(
        from: <String>['work stress', 'stressed about work'],
        path: 'feeling/stressed',
      ),
      TidySuggestion(from: <String>['payday', 'pay day'], path: 'event/payday'),
      TidySuggestion(from: <String>['bday'], path: 'event/birthday'),
    ];
  }
}

List<Override> _overrides({
  required OlderNotesProgress progress,
  required TagTidier tidier,
  required FakeTrackerWrites writes,
}) {
  final SealedFiles files = DeviceFiles(
    caches: () async => Directory.systemTemp,
    support: () async => Directory.systemTemp,
  ).keptForUser(ownerID, FakeFileSealer());
  return <Override>[
    userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
    todayProvider.overrideWith(() => FixedToday(_today)),
    trackerWritesProvider.overrideWithValue(writes),
    memoryJournal(MemoryJournalStore()),
    viceListProvider.overrideWithValue(
      AsyncData<List<Vice>>(<Vice>[
        fakeVice('wine', name: 'Wine', unit: Unit.drink),
        fakeVice('coffee', name: 'Coffee', unit: Unit.drink),
      ]),
    ),
    viceActivityRangeProvider.overrideWith(
      (Ref ref, ActivityRange range) => AsyncData<List<ViceActivity>>(_entries),
    ),
    allDayNotesProvider.overrideWithValue(AsyncData<List<DayNote>>(_dayNotes)),
    olderNoteReaderProvider.overrideWithValue(_FakeReader()),
    olderNotesFileProvider.overrideWithValue(OlderNotesFile(files)),
    olderNotesProvider.overrideWith(() => _FixedRunner(progress)),
    tagTidierProvider.overrideWithValue(tidier),
  ];
}

Future<void> _shot(WidgetTester tester, GlobalKey frame, String name) async {
  if (_dir.isEmpty) return;
  await tester.runAsync(() async {
    final ui.Image image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 3);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await Directory(_dir).create(recursive: true);
    await File('$_dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<GlobalKey> _open(
  WidgetTester tester,
  Brightness brightness,
  Widget page,
  List<Override> overrides,
) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final GlobalKey frame = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: page,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return frame;
}

void main() {
  setUpAll(loadRenderFonts);

  for (final Brightness b in Brightness.values) {
    testWidgets('older notes: the start screen says what will be sent '
        '(${b.name})', (WidgetTester tester) async {
      final GlobalKey frame = await _open(
        tester,
        b,
        const OlderNotesPage(),
        _overrides(
          progress: OlderNotesProgress(
            done: <String>{for (int i = 0; i < 12; i++) 'old$i'},
            day: '2026-11-16',
            sent: 12,
          ),
          tidier: _FakeTidier(),
          writes: FakeTrackerWrites(),
        ),
      );
      // a, b, c and old12 to old39.
      expect(find.text(OlderNotesPage.unread(31)), findsOneWidget);
      expect(find.text(OlderNotesPage.sends), findsOneWidget);
      expect(find.text(OlderNotesPage.readNext(20)), findsOneWidget);
      await _shot(tester, frame, 'older-notes-start-${b.name}');
    });

    testWidgets('older notes: the review list shows each note, its tags and '
        'their quotes (${b.name})', (WidgetTester tester) async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final GlobalKey frame = await _open(
        tester,
        b,
        const OlderNotesPage(),
        _overrides(progress: _review, tidier: _FakeTidier(), writes: writes),
      );
      expect(find.text('“boss tore into the roadmap”'), findsOneWidget);
      expect(find.text('Who was there › With friends'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Who was there › With friends'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _shot(tester, frame, 'older-notes-review-${b.name}');
      if (b == Brightness.dark) return;

      // Untick one tag, keep the rest of that note.
      await tester.tap(find.text('Who was there › With friends'));
      await tester.pump();
      await tester.tap(find.text(OlderNotesPage.keep).first);
      await tester.pump();
      await tester.pump();
      final Write w = writes.writes.single;
      expect(w.id, 'a');
      expect(w.fields['triggers'], <String>[
        'hungover',
        'work/meeting',
        'people/criticised',
      ]);
    });

    testWidgets('tidy: the labels are shown before anything is sent, and '
        'only accepted changes apply (${b.name})', (WidgetTester tester) async {
      final _FakeTidier tidier = _FakeTidier();
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final GlobalKey frame = await _open(
        tester,
        b,
        const TagTidyPage(),
        _overrides(progress: _review, tidier: tidier, writes: writes),
      );
      expect(find.text(TagTidyPage.found(9)), findsOneWidget);
      expect(find.text(TagTidyPage.sends), findsOneWidget);
      expect(tidier.sent, isEmpty);
      await _shot(tester, frame, 'tidy-labels-${b.name}');

      await tester.tap(find.text(TagTidyPage.send(9)));
      await tester.pump();
      await tester.pump();
      expect(tidier.sent.single, hasLength(9));
      expect(find.text(TagTidyPage.suggestions), findsOneWidget);
      await tester.tap(find.text(TagTidyPage.accept).first);
      await tester.pump();
      await tester.tap(find.text(TagTidyPage.accept).at(1));
      await tester.pump();
      await _shot(tester, frame, 'tidy-suggestions-${b.name}');
      if (b == Brightness.dark) return;

      await tester.scrollUntilVisible(
        find.text(TagTidyPage.apply(2)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text(TagTidyPage.apply(2)));
      await tester.pump();
      expect(find.text(TagTidyPage.applyTitle(2, 1)), findsOneWidget);
      expect(find.text(TagTidyPage.applyBody), findsOneWidget);
      await tester.tap(find.text(TagTidyPage.change));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        <String, Object?>{
          for (final Write w in writes.writes) w.id: w.fields['triggers'],
        },
        <String, Object?>{
          'd': <String>['hungover', 'bday'],
          'g': <String>['hungover', 'event/payday'],
          dayNoteID(ownerID, '2026-10-12'): <String>[
            'bored af',
            'event/payday',
          ],
        },
      );
    });
  }
}
