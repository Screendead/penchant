// A night out's Dart side: the count's arithmetic, the tile menu, the start
// sheet and Today's strip. Given a directory, also renders the three at
// 390x844, light and dark:
//   flutter test test/night_out_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/night_out/night_out.dart';
import 'package:tracker/night_out/night_out_sheet.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

Vice _vice(String id, String name, Unit unit, int order) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: false,
);

final List<Vice> _habits = <Vice>[
  _vice('coffee', 'Coffee', Unit.drink, 1),
  _vice('wine', 'Wine', Unit.drink, 2),
  _vice('scroll', 'Doomscrolling', Unit.minute, 3),
];

final DateTime _start = DateTime(2026, 11, 14, 19, 20);

final Night _night = Night(
  id: 'night',
  viceID: 'wine',
  start: _start,
  endBy: DateTime(2026, 11, 15, 3, 20),
  showsHabit: false,
  count: 3,
);

// How many times Today's End reached the notifier.
int _ends = 0;

class _FakeNightOut extends NightOutNotifier {
  _FakeNightOut(this._status);

  final NightOutStatus _status;

  @override
  NightOutStatus? build() => _status;

  @override
  Future<void> end() async {
    _ends++;
    state = _status.withNight(null);
  }
}

const NightOutStatus _ready = NightOutStatus(supported: true, enabled: true);

Future<void> _pumpToday(
  WidgetTester tester,
  NightOutStatus status, {
  GlobalKey? frame,
  Brightness brightness = Brightness.light,
}) async {
  final _FakeNightOut fake = _FakeNightOut(status);
  final User user = FakeUser(ownerID);
  final DateTime today = DateTime.now();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userProvider.overrideWith((ref) => Stream.value(user)),
        offlineProvider.overrideWith((ref) => Stream.value(false)),
        trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
        memoryJournal(),
        viceListProvider.overrideWith((ref) => AsyncData(_habits)),
        unarchivedViceListProvider.overrideWith((ref) => AsyncData(_habits)),
        viceActivityDayProvider.overrideWith(
          (ref, DateTime day) => AsyncData(<ViceActivity>[
            fakeActivity('coffee', 1, DateTime(today.year, today.month, 1, 8)),
          ]),
        ),
        nightOutProvider.overrideWith(() => fake),
      ],
      child: RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: const Homepage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester, String habit) async {
  await tester.longPress(find.text(habit).first);
  await tester.pumpAndSettle();
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

void main() {
  group('nightTotal', () {
    test('sums the habit since the start and names its entries', () {
      final List<ViceActivity> entries = <ViceActivity>[
        fakeActivity('wine', 2, _start),
        fakeActivity('coffee', 1, _start),
        fakeActivity('wine', 1, _start.add(const Duration(hours: 1))),
      ];
      final ({num base, List<String> seen}) total = nightTotal(entries, 'wine');
      expect(total.base, 3);
      expect(total.seen, <String>[entries[0].id, entries[2].id]);
    });
  });

  group('nightUnavailableReason', () {
    test('says why in one line, or nothing when it can start', () {
      expect(nightUnavailableReason(_ready), isNull);
      expect(
        nightUnavailableReason(NightOutStatus.unsupported),
        'Needs iOS 17 or later.',
      );
      expect(
        nightUnavailableReason(
          const NightOutStatus(supported: true, enabled: false),
        ),
        contains('Live Activities are off'),
      );
      expect(nightUnavailableReason(_ready.withNight(_night)), isNotNull);
    });
  });

  test('Night reads the channel map', () {
    final Night night = Night.fromMap(<Object?, Object?>{
      'id': 'x',
      'viceID': 'wine',
      'start': _start.millisecondsSinceEpoch.toDouble(),
      'endBy': _night.endBy.millisecondsSinceEpoch.toDouble(),
      'showsHabit': false,
      'count': 3.0,
    });
    expect(
      night,
      Night(
        id: 'x',
        viceID: 'wine',
        start: _start,
        endBy: _night.endBy,
        showsHabit: false,
        count: 3,
      ),
    );
  });

  testWidgets('Today shows the night running and ends it', (
    WidgetTester tester,
  ) async {
    _ends = 0;
    await _pumpToday(tester, _ready.withNight(_night));
    expect(find.text('Night out: Wine'), findsOneWidget);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(_ends, 1);
    expect(find.text('Night out: Wine'), findsNothing);
  });

  group('renders', () {
    setUpAll(_loadFonts);

    for (final Brightness brightness in Brightness.values) {
      for (final String scene in <String>['menu', 'sheet', 'running']) {
        testWidgets('$scene, ${brightness.name}', (WidgetTester tester) async {
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
          addTearDown(tester.view.reset);
          final GlobalKey frame = GlobalKey();
          await _pumpToday(
            tester,
            scene == 'running' ? _ready.withNight(_night) : _ready,
            frame: frame,
            brightness: brightness,
          );
          if (scene != 'running') {
            await _openMenu(tester, 'Wine');
          }
          if (scene == 'sheet') {
            await tester.tap(find.text(startNightLabel));
            await tester.pumpAndSettle();
          }
          await tester.runAsync(() async {
            final ui.Image image =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final ByteData? png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_dir/night-out-$scene-${brightness.name}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
        }, skip: _dir.isEmpty);
      }
    }
  });
}
