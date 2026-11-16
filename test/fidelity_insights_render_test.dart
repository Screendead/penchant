// Renders Insights with fake data in both themes: the question sections with
// last night at the top, the What it costs drill-in, the early days and not
// yet connected (docs/pitch/round-12/insights/built/):
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
import 'package:tracker/insights/insights_report.dart';
import 'package:tracker/insights/last_night.dart';
import 'package:tracker/insights/what_follows.dart';
import 'package:tracker/insights_page.dart';
import 'package:tracker/providers/insights_provider.dart';

import 'insights_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

const LastNight _night = LastNight(
  sleepingHeartRate: NightCompare(value: 57, usual: 54, low: 53, high: 55),
  heartRateVariability: NightCompare(value: 41, usual: 48, low: 45, high: 51),
  asleep: NightCompare(value: 410, usual: 435, low: 420, high: 450),
);

void main() {
  setUpAll(loadRenderFonts);
  for (final Brightness brightness in Brightness.values) {
    for (final (String name, double height) in <(String, double)>[
      ('questions', 1500),
      ('costs', 1200),
      ('early', 1100),
      ('connect', 844),
    ]) {
      testWidgets('insights $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          if (name != 'connect') healthConnectedKey: true,
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
              runner: name == 'early'
                  ? (_) async => InsightsReport(
                      findings: const <HabitFinding>[],
                      refused: <HabitRefusal>[
                        for (final (String habit, int days) in <(String, int)>[
                          ('coffee', 9),
                          ('tea', 6),
                        ])
                          HabitRefusal(
                            habitId: habit,
                            metricId: 'sleepDeep',
                            lagDays: 1,
                            usableDays: days,
                            exposedDays: days ~/ 2,
                            raw: null,
                            reason: RefusalReason.tooFewDays,
                          ),
                      ],
                    )
                  : null,
              lastNight: name == 'questions' ? _night : null,
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
        if (name == 'costs') {
          await tester.tap(find.text(InsightsPage.moreCosts));
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
            '$_dir/insights-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
