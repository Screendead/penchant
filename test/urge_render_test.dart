// Renders the urge feature at 390x844 in light and dark to PNGs: a tile's
// long-press menu, the urge sheet, Trends with urge marks, and a day's urges
// in Trends. Skipped unless a directory is given:
//   flutter test test/urge_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/urge.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/homepage.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/trends/trends_chart.dart';
import 'package:tracker/trends/trends_sheet.dart';
import 'package:tracker/widgets/tally_row.dart';

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
  _vice('wine', 'Wine', Unit.drink, 1),
  _vice('scroll', 'Doomscrolling', Unit.minute, 2),
  _vice('coffee', 'Coffee', Unit.drink, 3),
];

// Entries of Wine most evenings, a few each day.
List<ViceActivity> _entries(String viceID, DateTime start, DateTime end) =>
    <ViceActivity>[
      for (
        DateTime d = start;
        d.isBefore(end);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        for (int i = 0; i < (d.day * 7) % 4; i++)
          fakeActivity(viceID, 1, d.add(Duration(hours: 18 + i, minutes: 20))),
    ];

// Urges of Wine on most days, some that passed and some that became one.
List<Urge> _urges(DateTime today) => <Urge>[
  for (int back = 0; back < 30; back++)
    for (int i = 0; i < (back * 5) % 3; i++)
      Urge(
        id: 'urge-$back-$i',
        ownerID: ownerID,
        viceID: 'wine',
        createdAt: Timestamp.fromDate(
          addDays(today, -back).add(Duration(hours: 13 + i * 4, minutes: 10)),
        ),
        content: UrgeContent(
          strength: 1 + (back + i) % 5,
          outcome: UrgeOutcome.values[(back + i) % 3],
          outcomeAt: addDays(
            today,
            -back,
          ).add(Duration(hours: 13 + i * 4, minutes: 25)),
        ),
      ),
];

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
  final File icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
    'material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(
          Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
        ))
        .load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final Brightness brightness in Brightness.values) {
    for (final String scene in <String>[
      'menu',
      'sheet',
      'trends',
      'trends-day',
    ]) {
      testWidgets('renders urges, $scene, ${brightness.name}', (
        WidgetTester tester,
      ) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final DateTime today = startOfDay(DateTime.now());
        final GlobalKey frame = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...habitOverrides(_habits, urges: _urges(today)),
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              offlineProvider.overrideWith((ref) => Stream.value(false)),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              memoryJournal(),
              viceActivityDayProvider.overrideWith(
                (ref, DateTime day) => AsyncData(<ViceActivity>[
                  for (final Vice v in _habits.take(2))
                    ..._entries(v.id, day, addDays(day, 1)),
                ]),
              ),
              viceActivityGraphProvider.overrideWith(
                (ref, ViceActivityGraphQuery q) =>
                    AsyncData(_entries(q.viceID, q.start, q.end)),
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
        if (scene == 'menu' || scene == 'sheet') {
          await tester.longPress(
            find.byKey(const ValueKey<String>('tally-wine')),
          );
          await tester.pumpAndSettle();
        }
        if (scene == 'sheet') {
          await tester.tap(find.text(TallyRow.urgeAction));
          await tester.pumpAndSettle();
          await tester.tap(find.text('3'));
          await tester.pumpAndSettle();
        }
        if (scene.startsWith('trends')) {
          await tester.tap(find.text(TrendsSheet.title));
          await tester.pumpAndSettle();
        }
        if (scene == 'trends-day') {
          final Rect chart = tester.getRect(find.byType(TrendsChart));
          await tester.tapAt(Offset(chart.right - 6, chart.bottom - 60));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(TallyRow).last, const Offset(0, -400));
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
            '$_dir/urges-$scene-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}
