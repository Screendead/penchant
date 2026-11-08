// Captures 1f's motion every 16 ms, for reviewing it frame by frame:
//   flutter test test/motion_frames_render_test.dart --dart-define=RENDER_DIR=<dir>
// Each scene writes <dir>/<scene>/frame-NNN.png; tools/motion-frames.sh turns
// them into GIFs and contact sheets.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/day_dial.dart';

import 'fake_writes.dart';
import 'fakes.dart';
import 'render_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

final List<Vice> _vices = <Vice>[fakeVice('Coffee'), fakeVice('Tea')];

List<ViceActivity> _entries(DateTime day) => <ViceActivity>[
  for (final (int i, int minute) in <(int, int)>[
    (0, 8 * 60 + 10),
    (1, 10 * 60 + 30),
    (0, 13 * 60),
    (1, 16 * 60 + 45),
    (0, 19 * 60 + 20),
  ])
    fakeActivity(_vices[i].id, 1, day.add(Duration(minutes: minute))),
];

List<Override> _overrides() => <Override>[
  ...habitOverrides(_vices),
  userProvider.overrideWith((ref) => Stream.value(FakeUser(ownerID))),
  offlineProvider.overrideWith((ref) => Stream.value(false)),
  trackerWritesProvider.overrideWithValue(FakeTrackerWrites()),
  memoryJournal(),
  viceActivityDayProvider.overrideWith(
    (ref, DateTime day) => AsyncData(_entries(day)),
  ),
];

Future<void> Function() _recorder(
  WidgetTester tester,
  GlobalKey frame,
  String scene,
) {
  final Directory out = Directory('$_dir/$scene')..createSync(recursive: true);
  int n = 0;
  return () => tester.runAsync(() async {
    final ui.Image image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await File(
      '${out.path}/frame-${(n++).toString().padLeft(3, '0')}.png',
    ).writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<GlobalKey> _pumpToday(
  WidgetTester tester, {
  required bool reduced,
}) async {
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  addTearDown(tester.view.reset);
  final GlobalKey frame = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: RepaintBoundary(
        key: frame,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            devicePixelRatio: 2,
            disableAnimations: reduced,
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(Brightness.light),
            home: const Scaffold(body: SafeArea(child: ViceTracker())),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return frame;
}

Future<void> _run(
  WidgetTester tester,
  Future<void> Function() capture,
  int frames,
) async {
  await capture();
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await capture();
  }
  await tester.pumpAndSettle();
  debugDisableShadows = true;
}

void main() {
  setUpAll(loadRenderFonts);
  testWidgets('dial drag snap-back', (WidgetTester tester) async {
    final GlobalKey frame = await _pumpToday(tester, reduced: false);
    final Future<void> Function() capture = _recorder(tester, frame, 'snap');
    final TestGesture drag = await tester.startGesture(
      tester.getCenter(find.byType(DayDial)),
    );
    for (int i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await capture();
    await drag.up();
    await _run(tester, capture, 18);
  }, skip: _dir.isEmpty);

  testWidgets('reduce-motion day change', (WidgetTester tester) async {
    final GlobalKey frame = await _pumpToday(tester, reduced: true);
    final Future<void> Function() capture = _recorder(
      tester,
      frame,
      'reduced-day',
    );
    await capture();
    await tester.tap(find.byTooltip('Previous day'));
    await _run(tester, capture, 22);
  }, skip: _dir.isEmpty);
}
