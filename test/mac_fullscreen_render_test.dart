// Renders the Mac window at 2000x1250 (fullscreen on a 16" display) and
// 1200x780 (the default window), light and dark, with made-up habits, for the
// mac-fullscreen pitch. Skipped unless a directory is given:
//   flutter test test/mac_fullscreen_render_test.dart --dart-define=RENDER_DIR=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mac_window_harness.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

void main() {
  setUpAll(loadRenderFonts);

  for (final Brightness brightness in Brightness.values) {
    for (final Size size in const <Size>[Size(2000, 1250), Size(1200, 780)]) {
      final String name =
          '${size.width.toInt()}x${size.height.toInt()}-${brightness.name}';
      testWidgets('renders the Mac window, $name', (WidgetTester tester) async {
        final GlobalKey frame = GlobalKey();
        await pumpMacWindow(tester, size, brightness: brightness, frame: frame);

        await tester.runAsync(() async {
          final ui.Image image =
              await (frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final ByteData? png = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          Directory(_dir).createSync(recursive: true);
          await File(
            '$_dir/mac-$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }, skip: _dir.isEmpty);
    }
  }
}
