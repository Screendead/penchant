// Renders the amount sheet, new and editing, at the Day Dial mock-up's size,
// clock and record day (its time dial's faded entries), for side-by-side
// comparison with the mock-up's Record still (stills-record.png, frame 2;
// tools/fidelity/README.md):
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
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/vice_activity_editor_page.dart';
import 'package:tracker/widgets/record_new_activity_dialog.dart';
import 'package:tracker/widgets/time_dial.dart';

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
  Vice vice(String id, String name, Unit unit, int order) => Vice(
    id: id,
    name: name,
    unit: unit,
    ownerID: ownerID,
    createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, order)),
    archived: false,
  );
  // The mock-up's habits in its order, so Coffee takes the first mark.
  final List<Vice> habits = <Vice>[
    vice('coffee', 'Coffee', Unit.drink, 1),
    vice('takeaway', 'Takeaway', Unit.item, 2),
    vice('alcohol', 'Alcohol', Unit.drink, 3),
    vice('late', 'Late nights', Unit.time, 4),
    vice('scroll', 'Doomscrolling', Unit.minute, 5),
  ];
  // The mock-up's record day (fidelity_render_test.dart's 'record' scene):
  // habit, minute of the day, quantity.
  const List<(int, int, int)> record = <(int, int, int)>[
    (3, 40, 1),
    (0, 425, 1),
    (4, 440, 15),
    (0, 580, 1),
    (1, 770, 2),
    (4, 1005, 10),
  ];
  final DateTime today = DateTime(2026, 11, 5);
  final List<ViceActivity> recordDay = <ViceActivity>[
    for (final (int h, int minute, int q) in record)
      fakeActivity(habits[h].id, q, today.add(Duration(minutes: minute))),
  ];
  final DateTime at = DateTime(2026, 11, 5, 18, 30);
  final ViceActivity edited = fakeActivity('coffee', 2, at);

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
                  (ref, String id) => AsyncData(edited),
                ),
                viceActivityDayProvider.overrideWith(
                  (ref, DateTime day) => AsyncData(<ViceActivity>[
                    ...recordDay,
                    if (name == 'edit') edited,
                  ]),
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
            tester
                    .widget<EntryTimeField>(find.byType(EntryTimeField))
                    .controller
                    .at =
                at;
          } else {
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => ViceActivityEditorPage(
                  viceID: 'coffee',
                  activityID: edited.id,
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
