// Renders the Habits page with its Deleted habit row and the Deleted habit
// page, light and dark, at 390x844:
//   flutter test test/deleted_habit_render_test.dart --dart-define=RENDER_DIR=<dir>
// The stills in docs/pitch/round-13/built/ come from this.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/deleted_habit_page.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/main.dart';
import 'package:tracker/providers/deleted_habit_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final DateTime _now = DateTime(2026, 11, 9, 21, 10);

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
  final List<Vice> vices = <Vice>[
    fakeVice('coffee', name: 'Coffee', unit: Unit.drink),
    fakeVice('vape', name: 'Vape', unit: Unit.puff),
    fakeVice('sweets', name: 'Sweets', archived: true),
  ];
  final Map<String, int> counts = <String, int>{
    'coffee': 212,
    'vape': 480,
    'sweets': 37,
  };
  final List<ViceActivity> orphans = <ViceActivity>[
    fakeActivity('gone', 2, _now.subtract(const Duration(hours: 2))),
    fakeActivity(
      'gone',
      1,
      _now.subtract(const Duration(hours: 7, minutes: 20)),
      triggers: <String>['work/meeting'],
    ),
    fakeActivity('gone', 3, _now.subtract(const Duration(days: 1, hours: 3))),
    fakeActivity('gone', 1, _now.subtract(const Duration(days: 1, hours: 9))),
    fakeActivity('old', 4, _now.subtract(const Duration(days: 12, hours: 5))),
  ];

  for (final Brightness brightness in Brightness.values) {
    for (final String name in <String>['habits', 'page', 'confirm']) {
      testWidgets('deleted habit $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        debugDisableShadows = false;
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final GlobalKey frame = GlobalKey();
        await withClock(Clock.fixed(_now), () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
                memoryJournal(),
                userProvider.overrideWith(
                  (ref) => Stream.value(FakeUser(ownerID)),
                ),
                viceListProvider.overrideWithValue(AsyncData(vices)),
                activityTotalCountProvider.overrideWithValue(
                  AsyncData((
                    count: 729 + orphans.length,
                    source: CountSource.server,
                  )),
                ),
                viceActivityCountProvider.overrideWith(
                  (ref, String id) => AsyncData((
                    count: counts[id]!,
                    source: CountSource.server,
                  )),
                ),
                deletedHabitActivitiesProvider.overrideWithValue(
                  AsyncData(orphans),
                ),
              ],
              child: RepaintBoundary(
                key: frame,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: appTheme(Brightness.light),
                  darkTheme: appTheme(Brightness.dark),
                  initialRoute: name == 'habits'
                      ? '/manage-data'
                      : DeletedHabitPage.route,
                  onGenerateRoute: generateRoute,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (name == 'confirm') {
            await tester.tap(find.text(DeletedHabitPage.deleteAll));
            await tester.pumpAndSettle();
          }
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
            '$_dir/deleted-habit-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
