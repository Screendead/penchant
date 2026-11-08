// Renders the amount sheet, new and editing, at the Day Dial mock-up's size and
// clock, for side-by-side comparison with the mock-up's Record still
// (stills-record.png, frame 2; tools/fidelity/README.md):
//   flutter test test/fidelity_amount_sheet_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';

import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final DateTime _now = DateTime(2026, 11, 5, 21, 10);

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
  setUpAll(_loadFonts);
  final Vice coffee = Vice(
    id: 'coffee',
    name: 'Coffee',
    unit: Unit.drink,
    ownerID: ownerID,
    createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    archived: false,
  );
  // Coffee is the oldest habit, so it takes the first mark, as in the mock-up.
  final List<Vice> habits = <Vice>[
    coffee,
    Vice(
      id: 'tea',
      name: 'Tea',
      unit: Unit.drink,
      ownerID: ownerID,
      createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      archived: false,
    ),
  ];

  for (final Brightness brightness in Brightness.values) {
    for (final String name in <String>['new', 'edit']) {
      testWidgets('fidelity amount-sheet-$name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await withClock(Clock.fixed(_now), () async {
          debugDisableShadows = false;
          debugFormatLocales = const <Locale>[Locale('en', 'GB')];
          addTearDown(() => debugFormatLocales = null);
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = const Size(390 * 3, 844 * 3);
          tester.view.padding = const FakeViewPadding(
            top: 47 * 3,
            bottom: 34 * 3,
          );
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final GlobalKey frame = GlobalKey();
          final GlobalKey<NavigatorState> navigator =
              GlobalKey<NavigatorState>();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...habitOverrides(habits),
                trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
                userProvider.overrideWith(
                  (ref) => Stream.value(FakeUser(ownerID)),
                ),
                viceActivityProvider.overrideWith(
                  (ref, String id) => AsyncData(
                    fakeActivity('coffee', 2, DateTime(2026, 11, 5, 18, 30)),
                  ),
                ),
              ],
              child: RepaintBoundary(
                key: frame,
                child: MaterialApp(
                  navigatorKey: navigator,
                  debugShowCheckedModeBanner: false,
                  theme: appTheme(Brightness.light),
                  darkTheme: appTheme(Brightness.dark),
                  // The mock-up's clock is 24-hour.
                  builder: (BuildContext context, Widget? child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                  home: const Scaffold(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final BuildContext context = navigator.currentContext!;
          if (name == 'new') {
            RecordNewActivityDialog.show(context, initialViceID: 'coffee');
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Quantity'),
              '2',
            );
          } else {
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => ViceActivityEditorPage(
                  viceID: 'coffee',
                  activityID: fakeActivity(
                    'coffee',
                    2,
                    DateTime(2026, 11, 5, 18, 30),
                  ).id,
                ),
              ),
            );
          }
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final ui.Image image =
                await (frame.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final ByteData? png = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$_dir/app-amount-sheet-$name-${brightness.name}.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          });
          debugDisableShadows = true;
        });
      }, skip: _dir.isEmpty);
    }
  }
}
