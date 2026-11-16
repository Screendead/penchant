// Note search's states, and with a directory given, each as PNGs at 390x844
// in light and dark:
//   flutter test test/note_search_page_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/data/day_note.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/notes/follow_up.dart';
import 'package:tracker/notes/note_meaning.dart';
import 'package:tracker/notes/note_search_page.dart';
import 'package:tracker/providers/day_note_provider.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/today_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _today = DateTime(2026, 11, 16);

final List<Vice> _habits = <Vice>[
  fakeVice('wine', name: 'Wine'),
  fakeVice('coffee', name: 'Coffee'),
];

ViceActivity _entry(
  String id,
  String viceID,
  DateTime at, {
  String? note,
  FollowUp? followUp,
  bool locked = false,
}) => ViceActivity(
  id: id,
  viceID: viceID,
  quantity: 1,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(at),
  note: note,
  followUp: followUp,
  locked: locked,
);

final List<ViceActivity> _entries = <ViceActivity>[
  _entry(
    'e1',
    'wine',
    DateTime(2026, 11, 14, 22, 40),
    note: 'Sarah’s wedding. Open bar, lost count after the speeches.',
    followUp: const FollowUp(
      question: 'What made it a bigger night than usual?',
      answer: 'Everyone at the wedding was drinking, hard to say no.',
    ),
  ),
  _entry(
    'e2',
    'coffee',
    DateTime(2026, 11, 13, 9, 5),
    note: 'Third coffee before ten, the baby was up all night.',
  ),
  _entry(
    'e3',
    'wine',
    DateTime(2026, 10, 2, 19, 30),
    note: 'Rehearsal dinner for the wedding, kept it to two glasses.',
  ),
  _entry('e4', 'wine', DateTime(2026, 9, 1, 20), locked: true),
];

final List<DayNote> _dayNotes = <DayNote>[
  DayNote(
    id: 'd1',
    ownerID: ownerID,
    day: '2026-11-15',
    createdAt: Timestamp.fromDate(DateTime(2026, 11, 15, 21)),
    text: 'Slow day after the wedding, mostly on the sofa.',
  ),
];

class _Embedder implements SentenceEmbedder {
  @override
  Future<bool> available() async => true;

  @override
  Future<List<Float32List?>> embed(List<String> texts) async => <Float32List?>[
    for (final String _ in texts) null,
  ];
}

Future<void> _loadFonts() async {
  for (final (String family, String file) in <(String, String)>[
    (DialFonts.display, 'RedHatDisplay'),
    (DialFonts.text, 'RedHatText'),
    (DialFonts.mono, 'RedHatMono'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file-Variable.ttf'))).load();
  }
}

class _Today extends Today {
  @override
  DateTime build() => _today;
}

Future<List<String>> _pump(
  WidgetTester tester, {
  GlobalKey? frame,
  Brightness brightness = Brightness.light,
  List<ViceActivity>? entries,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final List<String> opened = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
        offlineProvider.overrideWith((ref) => Stream.value(false)),
        todayProvider.overrideWith(_Today.new),
        viceListProvider.overrideWithValue(AsyncData<List<Vice>>(_habits)),
        viceActivityRangeProvider.overrideWith(
          (ref, ActivityRange range) =>
              AsyncData<List<ViceActivity>>(entries ?? _entries),
        ),
        allDayNotesProvider.overrideWithValue(
          AsyncData<List<DayNote>>(_dayNotes),
        ),
        sentenceEmbedderProvider.overrideWithValue(_Embedder()),
        meaningAvailableProvider.overrideWith((ref) async => true),
      ],
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: const NoteSearchPage(),
          onGenerateRoute: (RouteSettings settings) {
            opened.add(settings.name!);
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('opened')),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty: says what it searches and that it stays here', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text(NoteSearchPage.onDevice), findsOneWidget);
    expect(find.text(NoteSearchPage.emptyPrompt), findsOneWidget);
    expect(find.text('5 notes to search.'), findsOneWidget);
    expect(find.text(NoteSearchPage.lockedLine(1)), findsOneWidget);
    expect(find.text(NoteSearchPage.meaningLabel), findsOneWidget);
  });

  testWidgets('results grouped by day, each opening its entry or day note', (
    WidgetTester tester,
  ) async {
    final List<String> opened = await _pump(tester);
    await _type(tester, 'Wedding');
    expect(find.text('4 notes'), findsOneWidget);
    expect(find.text('Day note'), findsOneWidget);
    expect(
      find.text('What made it a bigger night than usual?'),
      findsOneWidget,
    );
    final Finder dayNote = find.bySemanticsLabel(
      RegExp('^Day note, Slow day after the wedding'),
    );
    expect(dayNote, findsOneWidget);
    await tester.tap(dayNote);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    final Finder rehearsal = find.bySemanticsLabel(
      RegExp('^Wine, .*Rehearsal'),
    );
    await tester.ensureVisible(rehearsal);
    await tester.pumpAndSettle();
    await tester.tap(rehearsal);
    await tester.pumpAndSettle();
    expect(opened, <String>[
      '/day-notes/2026-11-15',
      '/vices/wine/activities/e3',
    ]);
  });

  testWidgets('no results says so', (WidgetTester tester) async {
    await _pump(tester);
    await _type(tester, 'funeral');
    expect(find.text(NoteSearchPage.noResults('funeral')), findsOneWidget);
  });

  testWidgets('no notes at all', (WidgetTester tester) async {
    await _pump(tester, entries: const <ViceActivity>[]);
    // The day note is still there.
    expect(find.text('1 note to search.'), findsOneWidget);
  });

  group('renders', () {
    setUpAll(_loadFonts);
    for (final Brightness brightness in Brightness.values) {
      for (final (String scene, String query) in <(String, String)>[
        ('empty', ''),
        ('results', 'the wedding'),
        ('no-results', 'funeral'),
      ]) {
        testWidgets('$scene, ${brightness.name}', (WidgetTester tester) async {
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
          addTearDown(tester.view.reset);
          final GlobalKey frame = GlobalKey();
          await _pump(tester, frame: frame, brightness: brightness);
          if (query.isNotEmpty) await _type(tester, query);
          await tester.runAsync(() async {
            final ui.Image image =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final ByteData? png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(_dir).create(recursive: true);
            await File(
              '$_dir/note-search-$scene-${brightness.name}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }, skip: _dir.isEmpty);
      }
    }
  });
}
