// Renders Today at 390x844, and the Mac's split view at 900, 1200 and 1600 pt
// wide, in light and dark to PNGs, for a look at the real fonts and colours. Skipped unless a directory is given:
//   flutter test test/today_render_test.dart --dart-define=RENDER_DIR=<dir>
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
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/log_fan.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

Vice _vice(
  String id,
  String name,
  Unit unit,
  int order, {
  bool archived = false,
}) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
  archived: archived,
);

final List<Vice> _habits = <Vice>[
  _vice('coffee', 'Coffee', Unit.drink, 1),
  _vice('takeaway', 'Takeaway', Unit.item, 2),
  _vice('alcohol', 'Alcohol', Unit.drink, 3),
  _vice('late', 'Late nights', Unit.time, 4),
  _vice('scroll', 'Doomscrolling', Unit.minute, 5),
  _vice('sugar', 'Sugar', Unit.item, 6, archived: true),
];

// The mock-up's busy day: habit, minute of the day, quantity.
const List<(int, int, int)> _busy = <(int, int, int)>[
  (3, 40, 1),
  (0, 425, 1),
  (4, 440, 15),
  (0, 580, 1),
  (0, 595, 1),
  (4, 750, 20),
  (1, 770, 2),
  (0, 795, 1),
  (0, 950, 1),
  (4, 1005, 10),
  (2, 1120, 1),
  (1, 1160, 3),
  (2, 1170, 2),
  (4, 1205, 35),
  (2, 1250, 1),
];

const List<(int, int, int)> _sparse = <(int, int, int)>[
  (0, 490, 1),
  (1, 1165, 1),
];

List<ViceActivity> _day(DateTime day, List<(int, int, int)> scene) =>
    <ViceActivity>[
      for (final (int h, int minute, int q) in scene)
        fakeActivity(_habits[h].id, q, day.add(Duration(minutes: minute))),
    ];

// A year of one habit, a few entries a day at hours that drift, so the
// chart, the stats and the hour ring all have something to show.
List<ViceActivity> _history(String viceID, DateTime start, DateTime end) {
  final List<ViceActivity> out = <ViceActivity>[];
  int seed = viceID.hashCode & 0xffff;
  int next(int bound) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % bound;
  }

  for (
    DateTime d = start;
    d.isBefore(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final int count = next(5);
    for (int i = 0; i < count; i++) {
      final int hour = (7 + next(4) + (i * 5)) % 24;
      out.add(
        fakeActivity(
          viceID,
          1 + next(2),
          d.add(Duration(hours: hour, minutes: next(60))),
        ),
      );
    }
  }
  return out;
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
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final File icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final Uint8List bytes = icons.readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final Brightness brightness in Brightness.values) {
    for (final (String scene, List<(int, int, int)> entries)
        in <(String, List<(int, int, int)>)>[
          ('busy', _busy),
          ('sparse', _sparse),
          ('clear', const <(int, int, int)>[]),
          ('fan', _sparse),
          ('trends', _busy),
          ('trends-day', _busy),
          ('trends-large', _busy),
          ('split-900', _busy),
          ('split-1200', _busy),
          ('split-1600', _busy),
          ('split-900-large', _busy),
        ]) {
      testWidgets('renders Today, $scene, ${brightness.name}', (
        WidgetTester tester,
      ) async {
        final double ratio = scene.startsWith('split') ? 2 : 3;
        tester.view.devicePixelRatio = ratio;
        if (scene.startsWith('split-')) {
          // A Mac window, which has no insets.
          final double width = double.parse(scene.split('-')[1]);
          tester.view.physicalSize = Size(width * 2, 800 * 2);
        } else {
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          // An iPhone's status bar and home indicator.
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
        }
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        if (scene.endsWith('-large')) {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final User user = FakeUser(ownerID);
        final GlobalKey frame = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProvider.overrideWith((ref) => Stream.value(user)),
              offlineProvider.overrideWith((ref) => Stream.value(false)),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              viceListProvider.overrideWith((ref) => AsyncData(_habits)),
              unarchivedViceListProvider.overrideWith(
                (ref) => AsyncData(<Vice>[
                  for (final Vice v in _habits)
                    if (!v.archived) v,
                ]),
              ),
              viceActivityDayProvider.overrideWith(
                (ref, DateTime day) => AsyncData(_day(day, entries)),
              ),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery q) =>
                    AsyncData(_history(q.viceID, q.start, q.end)),
              ),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: const Homepage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene == 'fan') {
          await tester.tap(find.byType(LogButton));
          await tester.pumpAndSettle();
        }
        if (scene.startsWith('split')) {
          // Yesterday, picked with the keyboard.
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pumpAndSettle();
        }
        if (scene.startsWith('trends')) {
          await tester.tap(find.text(TrendsSheet.title));
          await tester.pumpAndSettle();
        }
        if (scene == 'trends-day') {
          final Rect chart = tester.getRect(find.byType(TrendsChart));
          await tester.tapAt(Offset(chart.right - 40, chart.bottom - 60));
          await tester.pumpAndSettle();
        }

        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: ratio);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/today-$scene-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}
