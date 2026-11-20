// Say it to log and Catch up: the words, the draft entries, Save and Stop.
// With a directory, also renders the fan's Say it hub, listening, the
// catch-up page and the drafts at 390x844 in light and dark:
//   flutter test test/entry_words_page_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/claude/claude_working.dart';
import 'package:tracker/data/activity_content.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/say_it/entry_reader.dart';
import 'package:tracker/say_it/entry_words_page.dart';
import 'package:tracker/say_it/speech.dart';
import 'package:tracker/widgets/log_fan.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final DateTime _now = DateTime(2026, 11, 16, 21, 30);
final Vice _beer = fakeVice('beer', name: 'Beer', unit: Unit.drink);
final Vice _wine = fakeVice('wine', name: 'Wine', unit: Unit.drink);
final Vice _coffee = fakeVice('coffee', name: 'Coffee', unit: Unit.item);

class _Reader implements EntryReader {
  _Reader(this.reply);

  final Future<ReadEntries> Function(EntryMode mode) reply;
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  @override
  Future<ReadEntries> read(
    EntryMode mode,
    String text, {
    required DateTime now,
    required List<DateTime> days,
    required List<({int id, Vice vice})> habits,
  }) {
    sent.add(entryRequest(mode, text, now: now, days: days, habits: habits));
    return reply(mode);
  }
}

ReadEntries _drafts(EntryMode mode) => mode == EntryMode.now
    ? (
        entries: <DraftEntry>[
          DraftEntry(
            vice: _beer,
            amount: 2,
            at: DateTime(2026, 11, 16, 20, 30),
            note: 'two pints at the pub with Sam',
            triggers: const <String>['social/friends'],
          ),
          DraftEntry(
            vice: _coffee,
            amount: 1,
            at: DateTime(2026, 11, 16, 21, 30),
          ),
        ],
        dropped: 1,
      )
    : (
        entries: <DraftEntry>[
          DraftEntry(
            vice: _beer,
            amount: 4,
            at: DateTime(2026, 11, 13, 19),
            note: 'Fri about 4 pints from 7',
          ),
          DraftEntry(
            vice: _wine,
            amount: 6,
            at: DateTime(2026, 11, 14, 20),
            note: 'Sat a bottle of wine over dinner',
          ),
          DraftEntry(vice: _coffee, amount: 2, at: DateTime(2026, 11, 14, 10)),
        ],
        dropped: 0,
      );

class _Speech implements SpeechSource {
  StreamController<String>? words;

  @override
  Future<bool> available() async => true;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Stream<String> listen() {
    words = StreamController<String>();
    scheduleMicrotask(
      () => words?.add('two pints at the pub with Sam, about an hour ago'),
    );
    return words!.stream;
  }

  @override
  Future<void> stop() async {
    await words?.close();
    words = null;
  }
}

List<Override> _overrides(
  _Reader reader, {
  FakeTrackerWrites? writes,
  SpeechSource? speech,
  Map<String, double> typicals = const <String, double>{},
}) => <Override>[
  ...habitOverrides(<Vice>[_beer, _wine, _coffee], storedTypicals: typicals),
  userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
  trackerWritesProvider.overrideWithValue(writes ?? FakeTrackerWrites()),
  entryReaderProvider.overrideWith((Ref ref, EntryMode m) => reader),
  speechSourceProvider.overrideWithValue(speech),
  claudeWorkingMarksProvider.overrideWithValue(const <JournalMark>[]),
  memoryJournal(),
];

Widget _app(
  List<Override> overrides,
  Widget home, {
  Brightness brightness = Brightness.light,
  Key? frame,
}) => ProviderScope(
  overrides: overrides,
  child: RepaintBoundary(
    key: frame,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: brightness == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    ),
  ),
);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('entry-words-field')),
    text,
  );
  await tester.pump();
}

void main() {
  testWidgets('Say it: drafts are saved only on Save, marked spoken', (
    WidgetTester tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final _Reader reader = _Reader((EntryMode m) async => _drafts(m));
      await tester.pumpWidget(
        _app(
          _overrides(reader, writes: writes),
          const EntryWordsPage(mode: EntryMode.now),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(EntryWordsPage.listen), findsNothing);
      await _type(tester, 'two pints at the pub with Sam');
      await tester.tap(find.text(EntryWordsPage.read));
      await tester.pumpAndSettle();
      expect(reader.sent.single['mode'], 'now');
      expect(find.text('Beer'), findsOneWidget);
      expect(find.text(EntryWordsPage.leftOut(1)), findsOneWidget);
      expect(writes.writes, isEmpty);
      expect(find.text(EntryWordsPage.unclearSkipped), findsOneWidget);

      await tester.ensureVisible(find.text(EntryWordsPage.saveAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(EntryWordsPage.saveAll));
      await tester.pumpAndSettle();
      final List<Write> made = writes.writes
          .where((Write w) => w.op == 'recordActivity')
          .toList();
      expect(made, hasLength(2));
      expect(made.map((Write w) => w.fields['loggedVia']).toSet(), <Object?>{
        LoggedVia.spoken,
      });
      expect(made.first.fields['viceID'], 'beer');
      expect(made.first.fields['quantity'], 2);
      expect(made.first.fields['triggers'], <String>['social/friends']);
      expect(made.first.fields['note'], 'two pints at the pub with Sam');
      expect(find.text(EntryWordsPage.logged(2)), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        writes.writes.where((Write w) => w.op == 'deleteActivity'),
        hasLength(2),
      );
    });
  });

  testWidgets('a removed or edited draft is saved as it was left', (
    WidgetTester tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      await tester.pumpWidget(
        _app(
          _overrides(
            _Reader((EntryMode m) async => _drafts(m)),
            writes: writes,
            typicals: <String, double>{'beer': 0.5},
          ),
          const EntryWordsPage(mode: EntryMode.now),
        ),
      );
      await _type(tester, 'two pints');
      await tester.tap(find.text(EntryWordsPage.read));
      await tester.pumpAndSettle();
      // Two is four times the usual half: highlighted.
      expect(find.text(EntryWordsPage.aboveUsual), findsOneWidget);
      await tester.tap(find.byTooltip('More').first);
      await tester.pump();
      await tester.tap(find.byTooltip(EntryWordsPage.remove).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(EntryWordsPage.save));
      await tester.pumpAndSettle();
      final Write made = writes.writes.singleWhere(
        (Write w) => w.op == 'recordActivity',
      );
      expect(made.fields['viceID'], 'beer');
      expect(made.fields['quantity'], 3);
    });
  });

  testWidgets('Stop drops the answer: nothing shows and nothing saves', (
    WidgetTester tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final Completer<ReadEntries> answer = Completer<ReadEntries>();
      final FakeTrackerWrites writes = FakeTrackerWrites();
      await tester.pumpWidget(
        _app(
          _overrides(_Reader((_) => answer.future), writes: writes),
          const EntryWordsPage(mode: EntryMode.now),
        ),
      );
      await _type(tester, 'two pints');
      await tester.tap(find.text(EntryWordsPage.read));
      await tester.pump(ClaudeWorking.delay + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ClaudeWorking.stop));
      await tester.pumpAndSettle();
      answer.complete(_drafts(EntryMode.now));
      await tester.pumpAndSettle();
      expect(find.text('Beer'), findsNothing);
      expect(find.text('two pints'), findsOneWidget);
      expect(writes.writes, isEmpty);
    });
  });

  testWidgets('Catch up sends the picked days and marks entries caught up', (
    WidgetTester tester,
  ) async {
    await withClock(Clock.fixed(_now), () async {
      final FakeTrackerWrites writes = FakeTrackerWrites();
      final _Reader reader = _Reader((EntryMode m) async => _drafts(m));
      await tester.pumpWidget(
        _app(
          _overrides(reader, writes: writes),
          EntryWordsPage(
            mode: EntryMode.days,
            initialDays: <DateTime>[
              DateTime(2026, 11, 13),
              DateTime(2026, 11, 14),
              DateTime(2026, 11, 15),
            ],
          ),
        ),
      );
      await _type(tester, 'Fri about 4 pints from 7.');
      await tester.tap(find.text(EntryWordsPage.read));
      await tester.pumpAndSettle();
      expect(
        (reader.sent.single['dates']! as List<Object?>).map(
          (Object? d) => (d! as Map<String, Object?>)['date'],
        ),
        <String>['2026-11-13', '2026-11-14', '2026-11-15'],
      );
      await tester.scrollUntilVisible(
        find.text(EntryWordsPage.saveAll),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(EntryWordsPage.saveAll));
      await tester.pumpAndSettle();
      final List<Write> made = writes.writes
          .where((Write w) => w.op == 'recordActivity')
          .toList();
      expect(made, hasLength(3));
      expect(made.map((Write w) => w.fields['loggedVia']).toSet(), <Object?>{
        LoggedVia.caughtUp,
      });
    });
  });

  group('renders', () {
    setUpAll(() async {
      for (final (String family, String file) in <(String, String)>[
        (DialFonts.display, 'RedHatDisplay'),
        (DialFonts.text, 'RedHatText'),
        (DialFonts.mono, 'RedHatMono'),
      ]) {
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$file-Variable.ttf'))).load();
      }
    });

    for (final Brightness brightness in Brightness.values) {
      for (final String scene in <String>[
        'fan',
        'listening',
        'confirm',
        'catch-up',
        'catch-up-confirm',
      ]) {
        testWidgets('say it, $scene, ${brightness.name}', (
          WidgetTester tester,
        ) async {
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
          addTearDown(tester.view.reset);
          final GlobalKey frame = GlobalKey();
          await withClock(Clock.fixed(_now), () async {
            final _Reader reader = _Reader((EntryMode m) async => _drafts(m));
            final bool days = scene.startsWith('catch-up');
            final Map<String, HabitMark> marks = habitMarks(<Vice>[
              _beer,
              _wine,
              _coffee,
            ]);
            final Widget home = scene == 'fan'
                ? Scaffold(
                    body: Align(
                      alignment: const Alignment(0, 0.8),
                      child: LogButton(
                        habits: <FanHabit>[
                          for (final Vice v in <Vice>[_beer, _wine, _coffee])
                            (vice: v, mark: marks[v.id]!),
                        ],
                        onLog: (_, _) {},
                        onRecord: (_) {},
                        onSay: () {},
                      ),
                    ),
                  )
                : EntryWordsPage(
                    mode: days ? EntryMode.days : EntryMode.now,
                    initialDays: <DateTime>[
                      DateTime(2026, 11, 13),
                      DateTime(2026, 11, 14),
                      DateTime(2026, 11, 15),
                    ],
                  );
            await tester.pumpWidget(
              _app(
                _overrides(
                  reader,
                  speech: _Speech(),
                  typicals: <String, double>{'wine': 1},
                ),
                home,
                brightness: brightness,
                frame: frame,
              ),
            );
            await tester.pumpAndSettle();
            switch (scene) {
              case 'fan':
                await tester.tap(find.byType(LogButton));
                await tester.pumpAndSettle();
              case 'listening':
                await tester.tap(find.byKey(EntryWordsPage.micKey));
                await tester.pumpAndSettle();
              case 'catch-up':
                await _type(
                  tester,
                  'Fri about 4 pints from 7. Sat a bottle of wine over '
                  'dinner, two coffees. Sun nothing.',
                );
              default:
                await _type(tester, 'two pints at the pub with Sam');
                await tester.tap(find.text(EntryWordsPage.read));
                await tester.pumpAndSettle();
            }
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
          });
          await tester.runAsync(() async {
            final ui.Image image =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final ByteData? png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_dir/say-it-$scene-${brightness.name}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }, skip: _dir.isEmpty);
      }
    }
  });
}
