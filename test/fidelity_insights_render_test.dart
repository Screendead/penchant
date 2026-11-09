// Renders Insights with fake data, found and not yet connected, in both
// themes, for the pitch (docs/pitch/round-11/insights/):
//   flutter test test/fidelity_insights_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/health_source.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';

import 'insights_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  setUpAll(loadRenderFonts);
  for (final Brightness brightness in Brightness.values) {
    for (final (String name, double height) in <(String, double)>[
      ('found', 900),
      ('connect', 844),
    ]) {
      testWidgets('insights $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          if (name == 'found') healthConnectedKey: true,
        });
        debugDisableShadows = false;
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(390 * 3, height * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final GlobalKey frame = GlobalKey();
        final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: insightsOverrides(
              health: FakeHealthSource(
                read: HealthValues(insightsJournal().health),
              ),
            ),
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: const Scaffold(),
              ),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const InsightsPage()),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 3);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '$_dir/insights-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
