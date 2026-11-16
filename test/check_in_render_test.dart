// Renders random check-ins at 390x844 in light and dark to PNGs: the
// setting under Settings › Reminder, turned on, and the check-in sheet.
// Skipped unless a directory is given:
//   flutter test test/check_in_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/reminder/check_ins.dart';
import 'package:tracker/reminder/daily_nudge.dart';
import 'package:tracker/reminder_settings.dart';
import 'package:tracker/widgets/check_in_sheet.dart';

import 'check_in_test.dart' show FakeCheckInScheduler;
import 'fake_writes.dart';
import 'fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

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
    for (final String scene in <String>['settings', 'sheet']) {
      testWidgets('renders check-ins, $scene, ${brightness.name}', (
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
        SharedPreferences.setMockInitialValues(<String, Object>{
          CheckIns.enabledKey: true,
          CheckIns.startKey: 8 * 60 + 30,
          CheckIns.endKey: 22 * 60,
        });
        final GlobalKey frame = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              nudgeSchedulerProvider.overrideWithValue(FakeCheckInScheduler()),
              memoryJournal(),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: scene == 'settings'
                    ? const ReminderSettings()
                    : Builder(
                        builder: (BuildContext context) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () => CheckInSheet.show(
                                context,
                                checkInID: 'abc',
                                promptedAt: DateTime(2026, 11, 16, 14, 7),
                              ),
                              child: const Text('open'),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene == 'settings') {
          await tester.scrollUntilVisible(
            find.text(ReminderSettings.checkInFoot),
            200,
          );
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.text('open'));
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
            '$_dir/check-ins-$scene-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}
