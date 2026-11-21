// Renders the Backup page, a restore's confirmation and its result at
// 390x844, light and dark, to PNGs. Skipped unless a directory is given:
//   flutter test test/backup_render_test.dart --dart-define=RENDER_DIR=<dir>
@Tags(<String>['render'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/backup/backup_page.dart';
import 'package:tracker/backup/restore.dart';
import 'package:tracker/design/app_theme.dart';

import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

List<RestoreWrite> _writes(String collection, int n) => <RestoreWrite>[
  for (int i = 0; i < n; i++)
    RestoreWrite(collection, '$collection$i', const <String, Object>{}),
];

final RestorePlan _plan = RestorePlan(
  sourceUid: 'old',
  destinationUid: 'new',
  writes: <String, List<RestoreWrite>>{
    'vices': _writes('vices', 6),
    'activities': _writes('activities', 1843),
    'dayNotes': _writes('dayNotes', 41),
    'urges': _writes('urges', 12),
  },
  skipped: const <SkipReason, int>{
    SkipReason.habitMissing: 3,
    SkipReason.earlierKey: 1,
  },
  trimmed: 0,
);

final Map<String, Widget> _screens = <String, Widget>{
  'save': BackupSaveView(
    lastSaved: DateTime(2026, 10, 14),
    busy: false,
    guest: false,
    onSave: () {},
    onRestore: () {},
  ),
  'confirm': RestoreConfirmView(
    email: 'you@example.com',
    backupDate: DateTime(2026, 10, 14, 21, 5),
    plan: _plan,
    toWrite: _plan.total,
    alreadyThere: 0,
    onRestore: () {},
    onCancel: () {},
  ),
  'result': RestoreResultView(
    result: RestoreResult(
      written: <String, int>{
        for (final String c in restorableCollections) c: _plan.count(c),
      },
      alreadyThere: 0,
      skipped: _plan.skipped,
      trimmed: 0,
      planned: _plan.total,
    ),
    onDone: () {},
  ),
  'stopped': RestoreResultView(
    result: RestoreResult(
      written: const <String, int>{'vices': 6, 'activities': 400},
      alreadyThere: 0,
      skipped: const <SkipReason, int>{},
      trimmed: 0,
      planned: _plan.total,
      stoppedBy: StateError('connection lost'),
    ),
    onDone: () {},
  ),
};

void main() {
  setUpAll(loadRenderFonts);
  for (final Brightness brightness in Brightness.values) {
    for (final MapEntry<String, Widget>(key: String name, value: Widget screen)
        in _screens.entries) {
      testWidgets('backup $name ${brightness.name}', (
        WidgetTester tester,
      ) async {
        debugDisableShadows = false;
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.padding = const FakeViewPadding(
          top: 47 * 3,
          bottom: 34 * 3,
        );
        addTearDown(tester.view.reset);
        final GlobalKey frame = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(brightness),
              home: screen,
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
            '$_dir/backup-$name-${brightness.name}.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
        debugDisableShadows = true;
      }, skip: _dir.isEmpty);
    }
  }
}
