// Captures the sign-in screen every 16 ms while it switches to Create account
// and back, for reviewing the motion frame by frame:
//   flutter test test/auth_switch_frames_render_test.dart --dart-define=RENDER_DIR=<dir>
// tools/auth-switch-frames.sh turns the frames into a GIF and a contact sheet.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/authenticate.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/account_provider.dart';

import 'fake_account.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
const int _frames = 30;

void main() {
  setUpAll(loadRenderFonts);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  testWidgets('auth switch frames', (WidgetTester tester) async {
    debugDisableShadows = false;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
    addTearDown(tester.view.reset);
    final GlobalKey frame = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountProvider.overrideWithValue(FakeAccount())],
        child: RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(Brightness.light),
            home: const Authenticate(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Directory(_dir).createSync(recursive: true);
    int n = 0;
    Future<void> capture() => tester.runAsync(() async {
      final ui.Image image =
          await (frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await File(
        '$_dir/frame-${(n++).toString().padLeft(3, '0')}.png',
      ).writeAsBytes(png!.buffer.asUint8List());
    });
    for (final Key tab in <Key>[
      Authenticate.registerTab,
      Authenticate.signInTab,
    ]) {
      await capture();
      await tester.tap(find.byKey(tab));
      for (int i = 0; i < _frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await capture();
      }
      await tester.pumpAndSettle();
    }
    debugDisableShadows = true;
  }, skip: _dir.isEmpty);
}
