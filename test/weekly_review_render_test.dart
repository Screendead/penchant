// Renders the weekly review at 390x844 in both themes, its top and scrolled to
// the findings (docs/pitch/round-14/weekly-review/):
//   flutter test test/weekly_review_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/weekly_review_page.dart';

import 'render_fonts.dart';
import 'weekly_review_fixture.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  setUpAll(loadRenderFonts);
  for (final Brightness brightness in Brightness.values) {
    for (final String scene in <String>['top', 'findings']) {
      testWidgets('weekly review $scene ${brightness.name}', (
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
        await tester.pumpWidget(
          ProviderScope(
            overrides: reviewOverrides(),
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: const WeeklyReviewPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scene == 'findings') {
          await tester.scrollUntilVisible(
            find.text(WeeklyReviewPage.collectingHeading),
            200,
            scrollable: find.byType(Scrollable).first,
          );
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
            '$_dir/weekly-review-$scene-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
