// Renders the onboarding's four steps at the mock-up's size, for side-by-side
// comparison with the stills on mockup/onboarding-presets (plain-*.png):
//   flutter test test/fidelity_onboarding_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/onboarding/onboarding.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

Vice _habit(String id, String name, Unit unit) => Vice(
  id: id,
  name: name,
  unit: unit,
  ownerID: ownerID,
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
);

void main() {
  setUpAll(loadRenderFonts);
  for (final Brightness brightness in Brightness.values) {
    for (final (String name, OnboardingStep step) in <(String, OnboardingStep)>[
      ('1-intro', OnboardingStep.intro),
      ('2-picker', OnboardingStep.picker),
      ('3-disclaimer', OnboardingStep.disclaimer),
      ('4-first-log', OnboardingStep.firstLog),
    ]) {
      testWidgets('fidelity onboarding $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        debugDisableShadows = false;
        // The mock-up's stills are 1179 x 2556: a 393 x 852 pt phone at 3x.
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(393 * 3, 852 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 59 * 3,
          bottom: 34 * 3,
        );
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final GlobalKey frame = GlobalKey();
        // Newest first, as the query returns them.
        final List<Vice> habits = <Vice>[
          _habit('vape', 'Vape', Unit.puff),
          _habit('coffee', 'Coffee', Unit.drink),
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProvider.overrideWith(
                (ref) => Stream.value(FakeUser(ownerID)),
              ),
              ...habitOverrides(habits),
              trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
              memoryJournal(),
            ],
            child: RepaintBoundary(
              key: frame,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: appTheme(Brightness.light),
                darkTheme: appTheme(Brightness.dark),
                home: Onboarding(
                  onDone: () {},
                  initialStep: step,
                  initialSelection: const <String>{'Coffee', 'Vape'},
                ),
              ),
            ),
          ),
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
            '$_dir/app-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
